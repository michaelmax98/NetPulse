import SwiftUI
import AppKit
import Charts
import ServiceManagement

/// Collapsible section header chip — the shared design language of the
/// BetterBattery family.
struct SectionHeader: View {
    let icon: String
    let title: String
    let tint: [Color]   // one color = solid, two = gradient
    @Binding var expanded: Bool

    private var colors: [Color] {
        tint.count >= 2 ? tint : [tint.first ?? .gray, tint.first ?? .gray]
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .foregroundStyle(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            )
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.12) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

enum HistoryWindow: String, CaseIterable, Identifiable {
    case m15, h1, h24

    var id: String { rawValue }

    var label: String {
        switch self {
        case .m15: return "15m"
        case .h1: return "1h"
        case .h24: return "24h"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .m15: return 15 * 60
        case .h1: return 60 * 60
        case .h24: return 24 * 60 * 60
        }
    }
}

struct PanelView: View {
    @ObservedObject var monitor: NetMonitor
    @ObservedObject private var updater = UpdateChecker.shared
    @AppStorage(DefaultsKey.glyphMode) private var glyphModeRaw = GlyphMode.both.rawValue
    @AppStorage(DefaultsKey.useBits) private var useBits = false
    @AppStorage(DefaultsKey.historyWindow) private var historyWindowRaw = HistoryWindow.m15.rawValue
    @AppStorage(DefaultsKey.showSessionSection) private var showSessionSection = false
    @AppStorage(DefaultsKey.showInterfacesSection) private var showInterfacesSection = false
    @AppStorage(DefaultsKey.showSettingsSection) private var showSettingsSection = false
    @State private var launchAtLogin = false

    // SMAppService needs a real bundle; hide the toggle under `swift run`.
    private var canManageLoginItem: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Zone 1 — hero glance
            hero

            Divider()

            // Zone 2 — history
            chart

            Divider()

            // Zone 3 — collapsible sections, one chip language
            VStack(alignment: .leading, spacing: 6) {
                sessionSection
                interfacesSection
                settingsSection
            }

            Divider()

            // Zone 4 — update controls live at the very bottom of the panel
            // (standing user preference; keep them here in layout changes).
            footer
        }
        .padding(14)
        .frame(width: 324)
        .onAppear {
            if canManageLoginItem {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            monitor.refreshFriendlyNames()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heroColumn(symbol: "arrow.down", label: "Download", value: monitor.snapshot.downBps, color: NetAccent.down)
                Spacer(minLength: 4)
                heroColumn(symbol: "arrow.up", label: "Upload", value: monitor.snapshot.upBps, color: NetAccent.up)
            }
            Label(
                monitor.snapshot.online
                    ? "Online" + (monitor.snapshot.activeName.map { " — \($0)" } ?? "")
                    : "Offline",
                systemImage: monitor.snapshot.online ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(monitor.snapshot.online ? AnyShapeStyle(.secondary) : AnyShapeStyle(NetAccent.offline))
        }
    }

    private func heroColumn(symbol: String, label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(NetFormat.rate(value, bits: useBits))
                    .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Samples land once a second; ease between them so the
                    // readout reads as a moving rate rather than a stutter.
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: value)
            }
            .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart

    private var windowedSamples: [NetSample] {
        let window = HistoryWindow(rawValue: historyWindowRaw) ?? .m15
        let cutoff = Date().addingTimeInterval(-window.seconds)
        // history is append-ordered, so the cutoff can be found by bisection
        // instead of scanning all 17,280 retained samples. This runs on every
        // body evaluation — i.e. once a second while the panel is open.
        let samples = monitor.history
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date >= cutoff { high = mid } else { low = mid + 1 }
        }
        let filtered = Array(samples[low...])
        let maxPoints = 160
        guard filtered.count > maxPoints else { return filtered }
        let bucketSize = filtered.count / maxPoints + 1
        var bucketed: [NetSample] = []
        var index = 0
        while index < filtered.count {
            let slice = filtered[index..<min(index + bucketSize, filtered.count)]
            let down = slice.reduce(0.0) { $0 + $1.downBps } / Double(slice.count)
            let up = slice.reduce(0.0) { $0 + $1.upBps } / Double(slice.count)
            bucketed.append(NetSample(date: slice[slice.startIndex].date, downBps: down, upBps: up))
            index += bucketSize
        }
        return bucketed
    }

    private var chart: some View {
        let points = windowedSamples
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                legendChip(color: NetAccent.down, label: "Down")
                legendChip(color: NetAccent.up, label: "Up")
                Spacer()
                Picker("Window", selection: $historyWindowRaw) {
                    ForEach(HistoryWindow.allCases) { window in
                        Text(window.label).tag(window.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 126)
            }
            if points.count < 2 {
                Text("Collecting samples…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Down", point.downBps)
                        )
                        .foregroundStyle(NetAccent.down.opacity(0.14))
                        .interpolationMethod(.monotone)
                    }
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Down", point.downBps),
                            series: .value("Series", "down")
                        )
                        .foregroundStyle(NetAccent.down)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                    }
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Up", point.upBps),
                            series: .value("Series", "up")
                        )
                        .foregroundStyle(NetAccent.up)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bps = value.as(Double.self) {
                                Text(NetFormat.axis(bps, bits: useBits))
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .frame(height: 84)
            }
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Session

    @ViewBuilder
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                icon: "sum",
                title: "This Session",
                tint: [NetAccent.down, NetAccent.up],
                expanded: $showSessionSection
            )

            if showSessionSection {
                VStack(alignment: .leading, spacing: 5) {
                    statRow(label: "Downloaded", value: NetFormat.bytes(monitor.snapshot.sessionDownBytes), color: NetAccent.down)
                    statRow(label: "Uploaded", value: NetFormat.bytes(monitor.snapshot.sessionUpBytes), color: NetAccent.up)
                    statRow(label: "Peak down", value: NetFormat.rate(monitor.snapshot.peakDownBps, bits: useBits), color: Color.secondary)
                    statRow(label: "Peak up", value: NetFormat.rate(monitor.snapshot.peakUpBps, bits: useBits), color: Color.secondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }

    // MARK: - Interfaces

    @ViewBuilder
    private var interfacesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                icon: "network",
                title: "Interfaces",
                tint: [NetAccent.down],
                expanded: $showInterfacesSection
            )

            if showInterfacesSection {
                VStack(alignment: .leading, spacing: 6) {
                    if monitor.snapshot.interfaces.isEmpty {
                        Text("No active interfaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.snapshot.interfaces) { row in
                            interfaceRow(row)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private func interfaceRow(_ row: InterfaceRate) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(row.running ? NetAccent.up : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(row.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if row.isVPN {
                        Text("VPN")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(NetAccent.down.opacity(0.15)))
                            .foregroundStyle(NetAccent.down)
                    }
                }
                Text(row.bsdName)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("▾ " + NetFormat.rate(row.downBps, bits: useBits))
                    .foregroundStyle(NetAccent.down)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: row.downBps)
                Text("▴ " + NetFormat.rate(row.upBps, bits: useBits))
                    .foregroundStyle(NetAccent.up)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: row.upBps)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "gearshape.fill", title: "Settings", tint: [.gray], expanded: $showSettingsSection)

            if showSettingsSection {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Menu bar shows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Menu bar shows", selection: $glyphModeRaw) {
                            ForEach(GlyphMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle("Show speeds in bits (Mbps)", isOn: $useBits)
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                    if canManageLoginItem {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: launchAtLogin) { enabled in
                                updateLoginItem(enabled)
                            }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Footer (update controls + Quit, single row)

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let available = updater.availableVersion {
                HStack(spacing: 8) {
                    Label("v\(available) available", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button(updater.isInstalling ? "Installing…" : "Install Update") {
                        updater.installUpdate()
                    }
                    .controlSize(.small)
                    .disabled(updater.isInstalling)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                    .keyboardShortcut("q")
                }
            } else {
                HStack(spacing: 8) {
                    if updater.currentVersion != nil {
                        Button(updater.isChecking ? "Checking…" : "Check for Updates") {
                            updater.check(userInitiated: true)
                        }
                        .controlSize(.small)
                        .disabled(updater.isChecking)
                    }
                    if let current = updater.currentVersion {
                        Text("v\(current)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: "https://buymeacoffee.com/michaelmaxwell") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "cup.and.saucer.fill")
                    }
                    .controlSize(.small)
                    .help("Enjoying it? Buy me a coffee")
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                    .keyboardShortcut("q")
                }
            }
            if let status = updater.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
