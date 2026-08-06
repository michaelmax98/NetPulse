import SwiftUI
import AppKit

enum NetAccent {
    static let down = Color(red: 0.30, green: 0.62, blue: 1.00)
    static let up = Color(red: 0.25, green: 0.78, blue: 0.45)
    static let offline = Color(red: 1.00, green: 0.33, blue: 0.30)
}

enum GlyphMode: String, CaseIterable, Identifiable {
    case both, down, up, icon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: return "Both"
        case .down: return "Down"
        case .up: return "Up"
        case .icon: return "Icon"
        }
    }
}

/// The fixed-width menu bar glyph — same footprint in every mode so the menu
/// bar never shifts as values change. Offline renders a dim wifi.slash in
/// every mode: quiet and readable, never a wall of red text.
struct NetGlyph: View {
    let mode: GlyphMode
    let downText: String
    let upText: String
    let online: Bool
    let darkMenuBar: Bool

    static let width: CGFloat = 46
    static let height: CGFloat = 18

    private var baseColor: Color { darkMenuBar ? .white : .black }

    var body: some View {
        Group {
            if !online {
                offline
            } else {
                switch mode {
                case .both:
                    stacked
                case .down:
                    single(text: downText, symbol: "arrowtriangle.down.fill", color: NetAccent.down)
                case .up:
                    single(text: upText, symbol: "arrowtriangle.up.fill", color: NetAccent.up)
                case .icon:
                    icon
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
    }

    private var offline: some View {
        Image(systemName: "wifi.slash")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(baseColor.opacity(0.75))
    }

    private var stacked: some View {
        VStack(alignment: .trailing, spacing: 0) {
            row(text: downText, symbol: "arrowtriangle.down.fill", color: NetAccent.down)
            row(text: upText, symbol: "arrowtriangle.up.fill", color: NetAccent.up)
        }
    }

    // Direction is carried by the arrow's colour alone. Tinted digits this
    // small are hard to read against the menu bar, so the numbers take the
    // menu bar's own foreground: white on dark, black on light.
    private func row(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 1.5) {
            Image(systemName: symbol)
                .font(.system(size: 5.5, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(baseColor)
        }
    }

    private func single(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(baseColor)
        }
    }

    private var icon: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(baseColor.opacity(0.9))
    }
}

/// Renders the glyph offscreen to an NSImage — the status item pipeline
/// mangles live layered SwiftUI views. Re-renders only when the visible
/// content actually changed, so idle traffic costs zero drawing per tick.
struct MenuBarLabel: View {
    @ObservedObject var monitor: NetMonitor
    @AppStorage(DefaultsKey.glyphMode) private var glyphModeRaw = GlyphMode.both.rawValue
    @AppStorage(DefaultsKey.useBits) private var useBits = false
    @Environment(\.colorScheme) private var colorScheme

    private final class RenderCache {
        var key = ""
        var image: NSImage?
    }
    private static let cache = RenderCache()

    var body: some View {
        let mode = GlyphMode(rawValue: glyphModeRaw) ?? .both
        let downText = NetFormat.compact(monitor.snapshot.downBps, bits: useBits)
        let upText = NetFormat.compact(monitor.snapshot.upBps, bits: useBits)
        let online = monitor.snapshot.online
        let darkMenuBar = colorScheme == .dark
        let key = "\(mode.rawValue)|\(downText)|\(upText)|\(online)|\(darkMenuBar)"

        let image: NSImage
        if key == Self.cache.key, let cached = Self.cache.image {
            image = cached
        } else {
            let glyph = NetGlyph(mode: mode, downText: downText, upText: upText, online: online, darkMenuBar: darkMenuBar)
            let renderer = ImageRenderer(content: glyph)
            renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
            let rendered = renderer.nsImage ?? NSImage(size: NSSize(width: NetGlyph.width, height: NetGlyph.height))
            rendered.isTemplate = false
            Self.cache.key = key
            Self.cache.image = rendered
            image = rendered
        }
        return Image(nsImage: image)
    }
}
