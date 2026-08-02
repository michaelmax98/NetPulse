import Foundation
import AppKit
import Combine
import SystemConfiguration
import Darwin

// MARK: - Data shapes

struct InterfaceRate: Identifiable {
    let id: String
    let bsdName: String
    let displayName: String
    let isVPN: Bool
    let running: Bool
    let downBps: Double
    let upBps: Double
}

struct NetSnapshot {
    var downBps: Double = 0
    var upBps: Double = 0
    var online = false
    var activeName: String?
    var interfaces: [InterfaceRate] = []
    var sessionDownBytes: UInt64 = 0
    var sessionUpBytes: UInt64 = 0
    var peakDownBps: Double = 0
    var peakUpBps: Double = 0
}

struct NetSample: Identifiable {
    let date: Date
    let downBps: Double
    let upBps: Double
    var id: Date { date }
}

// MARK: - Counter sampling

/// One reading of an interface's lifetime byte counters.
struct LinkCounters {
    let name: String
    let running: Bool
    let inBytes: UInt64
    let outBytes: UInt64
}

/// Reads every interface's traffic counters in a single sysctl call — the
/// same public route-table listing `netstat -ib` prints. Microseconds per
/// read, no processes spawned, no permissions, no allocations beyond the
/// reply buffer.
enum NetSampler {
    // RTM_IFINFO2 from <net/route.h>; these records carry 64-bit counters.
    private static let ifInfo2: UInt8 = 0x12

    static func readAll() -> [LinkCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var needed = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &needed, nil, 0) == 0 else { return [] }

        let total = needed
        var links: [LinkCounters] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            // Every routing message starts with the same prefix: u_short
            // msglen, u_char version, u_char type. Walk by msglen. Only the
            // RTM_IFINFO2 records are full if_msghdr2 structs with counters;
            // the interface-address records interleaved between them are
            // shorter and are simply skipped, never a reason to stop.
            while offset + 4 <= total {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                let messageType = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
                guard messageLength > 0, offset + messageLength <= total else { break }
                if messageType == ifInfo2, offset + MemoryLayout<if_msghdr2>.size <= total {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBytes = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    var name = ""
                    if if_indextoname(UInt32(message.ifm_index), &nameBytes) != nil {
                        name = String(cString: nameBytes)
                    }
                    let flags = UInt32(bitPattern: message.ifm_flags)
                    let isUp = flags & UInt32(bitPattern: IFF_UP) != 0
                    let isRunning = flags & UInt32(bitPattern: IFF_RUNNING) != 0
                    if !name.isEmpty {
                        links.append(LinkCounters(
                            name: name,
                            running: isUp && isRunning,
                            inBytes: message.ifm_data.ifi_ibytes,
                            outBytes: message.ifm_data.ifi_obytes
                        ))
                    }
                }
                offset += messageLength
            }
        }
        return links
    }
}

// MARK: - Monitor

final class NetMonitor: ObservableObject {
    @Published private(set) var snapshot = NetSnapshot()
    @Published private(set) var history: [NetSample] = []

    /// ~24h of 5-second-averaged samples, RAM only — nothing touches disk.
    private static let historyCap = 17_280
    private static let averagingWindow = 5

    private var timer: Timer?
    private var previous: [String: (inBytes: UInt64, outBytes: UInt64)] = [:]
    private var previousDate: Date?
    private var pending: [(down: Double, up: Double)] = []
    private var friendlyNames: [String: String] = [:]
    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0
    private var peakDown: Double = 0
    private var peakUp: Double = 0

    init() {
        refreshFriendlyNames()
        start()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(displaysDidSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    // Displays off means nobody is looking: stop sampling and rendering
    // entirely, then rebase counters on wake so the gap never spikes a chart.
    @objc private func displaysDidSleep() {
        timer?.invalidate()
        timer = nil
        pending.removeAll()
    }

    @objc private func displaysDidWake() {
        previous.removeAll()
        previousDate = nil
        start()
    }

    func refreshFriendlyNames() {
        guard let all = (SCNetworkInterfaceCopyAll() as NSArray) as? [SCNetworkInterface] else { return }
        var map: [String: String] = [:]
        for interface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                map[bsd] = name
            }
        }
        friendlyNames = map
    }

    private func tick() {
        let now = Date()
        let links = NetSampler.readAll()
        let elapsed = previousDate.map { now.timeIntervalSince($0) } ?? 0
        let usable = elapsed > 0.2 && elapsed < 10

        var totalDownDelta: UInt64 = 0
        var totalUpDelta: UInt64 = 0
        var rows: [InterfaceRate] = []
        var busiestName: String?
        var busiestActivity: UInt64 = 0
        var anyPhysicalRunning = false

        for link in links {
            // Physical traffic rides en* (Wi-Fi, Ethernet, tethering). VPN
            // tunnels (utun/ppp) are listed for visibility but excluded from
            // totals — their packets traverse en* too and would double-count.
            let physical = link.name.hasPrefix("en")
            let vpn = link.name.hasPrefix("utun") || link.name.hasPrefix("ppp")
            guard physical || vpn else { continue }

            var downDelta: UInt64 = 0
            var upDelta: UInt64 = 0
            if usable, let prev = previous[link.name] {
                if link.inBytes >= prev.inBytes { downDelta = link.inBytes - prev.inBytes }
                if link.outBytes >= prev.outBytes { upDelta = link.outBytes - prev.outBytes }
            }
            previous[link.name] = (link.inBytes, link.outBytes)

            let downBps = usable ? Double(downDelta) / elapsed : 0
            let upBps = usable ? Double(upDelta) / elapsed : 0

            if physical {
                anyPhysicalRunning = anyPhysicalRunning || link.running
                totalDownDelta &+= downDelta
                totalUpDelta &+= upDelta
                let activity = downDelta &+ upDelta
                if link.running && (busiestName == nil || activity > busiestActivity) {
                    busiestName = link.name
                    busiestActivity = activity
                }
            }

            if link.running || downBps > 0 || upBps > 0 {
                rows.append(InterfaceRate(
                    id: link.name,
                    bsdName: link.name,
                    displayName: friendlyNames[link.name] ?? (vpn ? "VPN tunnel" : link.name),
                    isVPN: vpn,
                    running: link.running,
                    downBps: downBps,
                    upBps: upBps
                ))
            }
        }

        rows.sort { a, b in
            if a.isVPN != b.isVPN { return !a.isVPN }
            return a.bsdName < b.bsdName
        }

        let downBps = usable ? Double(totalDownDelta) / elapsed : 0
        let upBps = usable ? Double(totalUpDelta) / elapsed : 0
        sessionDown &+= totalDownDelta
        sessionUp &+= totalUpDelta
        peakDown = max(peakDown, downBps)
        peakUp = max(peakUp, upBps)

        var next = NetSnapshot()
        next.downBps = downBps
        next.upBps = upBps
        next.online = anyPhysicalRunning
        next.activeName = busiestName.map { friendlyNames[$0] ?? $0 }
        next.interfaces = rows
        next.sessionDownBytes = sessionDown
        next.sessionUpBytes = sessionUp
        next.peakDownBps = peakDown
        next.peakUpBps = peakUp
        snapshot = next

        previousDate = now

        if usable {
            pending.append((downBps, upBps))
            if pending.count >= Self.averagingWindow {
                let downAvg = pending.reduce(0.0) { $0 + $1.down } / Double(pending.count)
                let upAvg = pending.reduce(0.0) { $0 + $1.up } / Double(pending.count)
                pending.removeAll(keepingCapacity: true)
                history.append(NetSample(date: now, downBps: downAvg, upBps: upAvg))
                if history.count > Self.historyCap {
                    history.removeFirst(history.count - Self.historyCap)
                }
            }
        }
    }
}

// MARK: - Formatting

enum NetFormat {
    /// "2.4 MB/s" or, in bits mode, "19.2 Mbps".
    static func rate(_ bytesPerSecond: Double, bits: Bool) -> String {
        let (value, unit) = scaled(bytesPerSecond, bits: bits)
        let digits = value >= 100 ? 0 : 1
        return String(format: "%.\(digits)f %@", value, unit)
    }

    /// Compact menu bar form: "2.4M", "180K", "0".
    static func compact(_ bytesPerSecond: Double, bits: Bool) -> String {
        let value = bits ? bytesPerSecond * 8 : bytesPerSecond
        switch value {
        case ..<500:
            return "0"
        case ..<999_500:
            return String(format: "%.0fK", value / 1_000)
        case ..<9_995_000:
            return String(format: "%.1fM", value / 1_000_000)
        case ..<999_500_000:
            return String(format: "%.0fM", value / 1_000_000)
        default:
            return String(format: "%.1fG", value / 1_000_000_000)
        }
    }

    /// Chart axis form: "2M", "500K".
    static func axis(_ bytesPerSecond: Double, bits: Bool) -> String {
        let value = bits ? bytesPerSecond * 8 : bytesPerSecond
        switch value {
        case ..<1_000:
            return String(format: "%.0f", value)
        case ..<1_000_000:
            return String(format: "%.0fK", value / 1_000)
        case ..<1_000_000_000:
            return String(format: "%.1fM", value / 1_000_000)
        default:
            return String(format: "%.1fG", value / 1_000_000_000)
        }
    }

    /// "1.24 GB" for totals (totals are always bytes).
    static func bytes(_ total: UInt64) -> String {
        let value = Double(total)
        switch value {
        case ..<1_000:
            return String(format: "%.0f B", value)
        case ..<1_000_000:
            return String(format: "%.0f KB", value / 1_000)
        case ..<1_000_000_000:
            return String(format: "%.2f MB", value / 1_000_000)
        default:
            return String(format: "%.2f GB", value / 1_000_000_000)
        }
    }

    private static func scaled(_ bytesPerSecond: Double, bits: Bool) -> (Double, String) {
        let value = bits ? bytesPerSecond * 8 : bytesPerSecond
        let units = bits ? ["bps", "Kbps", "Mbps", "Gbps"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaledValue = value
        var index = 0
        while scaledValue >= 1_000 && index < units.count - 1 {
            scaledValue /= 1_000
            index += 1
        }
        return (scaledValue, units[index])
    }
}
