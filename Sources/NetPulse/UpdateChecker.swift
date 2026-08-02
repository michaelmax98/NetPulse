import Foundation
import AppKit
import Combine
import CryptoKit

/// Checks the GitHub Releases feed for a newer version and installs it in
/// place: download the DMG, verify its published sha256, mount it, swap the
/// app bundle, strip quarantine, and relaunch — one click, no dragging.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repoSlug = "michaelmax98/NetPulse"

    @Published private(set) var availableVersion: String?
    @Published private(set) var releasePage: URL?
    @Published private(set) var dmgURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusMessage: String?

    private var expectedSHA256: String?

    /// nil when running unbundled via `swift run`; updates are disabled then.
    var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var timer: Timer?

    private init() {
        guard currentVersion != nil else { return }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.check(userInitiated: false)
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Checking

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let digest: String?
        }
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    func check(userInitiated: Bool) {
        guard let current = currentVersion, !isChecking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repoSlug)/releases/latest") else { return }
        DispatchQueue.main.async {
            self.isChecking = true
            if userInitiated { self.statusMessage = nil }
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            var newVersion: String?
            var page: URL?
            var dmg: URL?
            var sha: String?
            var message: String?
            if let data, let release = try? JSONDecoder().decode(Release.self, from: data) {
                let latest = release.tag_name.hasPrefix("v")
                    ? String(release.tag_name.dropFirst())
                    : release.tag_name
                if Self.isVersion(latest, newerThan: current) {
                    newVersion = latest
                    page = URL(string: release.html_url)
                    if let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                        dmg = URL(string: asset.browser_download_url)
                        sha = asset.digest?.replacingOccurrences(of: "sha256:", with: "")
                    }
                } else if userInitiated {
                    message = "You're up to date (v\(current))."
                }
            } else if userInitiated {
                message = "Couldn't check for updates — try again later."
            }
            DispatchQueue.main.async {
                self.isChecking = false
                self.availableVersion = newVersion
                self.releasePage = page
                self.dmgURL = dmg
                self.expectedSHA256 = sha
                if let message { self.statusMessage = message }
            }
        }.resume()
    }

    // MARK: - Installing

    func installUpdate() {
        guard !isInstalling else { return }
        guard let downloadURL = dmgURL else {
            if let releasePage { NSWorkspace.shared.open(releasePage) }
            return
        }
        DispatchQueue.main.async {
            self.isInstalling = true
            self.statusMessage = "Downloading update…"
        }
        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, _ in
            guard let self else { return }
            guard let tempURL else {
                self.finishInstall(message: "Download failed — try again later.")
                return
            }
            // The download's temp file is deleted when this closure returns,
            // so move it into our own working directory first.
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("NetPulseUpdate-\(UUID().uuidString)")
            let dmgPath = workDir.appendingPathComponent("update.dmg")
            do {
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tempURL, to: dmgPath)
            } catch {
                self.finishInstall(message: "Couldn't save the update — try again later.")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.performInstall(dmg: dmgPath, workDir: workDir)
            }
        }.resume()
    }

    private func performInstall(dmg: URL, workDir: URL) {
        let fm = FileManager.default

        // Verify against the sha256 GitHub publishes for the release asset.
        if let expected = expectedSHA256, !expected.isEmpty,
           let data = try? Data(contentsOf: dmg) {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if actual.lowercased() != expected.lowercased() {
                try? fm.removeItem(at: workDir)
                finishInstall(message: "Update failed verification and was not installed.")
                return
            }
        }

        DispatchQueue.main.async { self.statusMessage = "Installing update…" }

        let mountPoint = workDir.appendingPathComponent("mount")
        try? fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noverify", "-quiet",
                                       "-mountpoint", mountPoint.path]) == 0 else {
            fallbackToManual(dmg: dmg, message: "Couldn't open the update image.")
            return
        }

        // Find whatever app the update image contains — the app may be
        // renamed between versions, so never hardcode the bundle name.
        let mountedApp = (try? fm.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "app" }
        let destination = Bundle.main.bundleURL
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".NetPulse-update.app")

        var swapped = false
        var installedURL = destination
        if let mountedApp {
            let finalURL = destination.deletingLastPathComponent()
                .appendingPathComponent(mountedApp.lastPathComponent)
            do {
                try? fm.removeItem(at: staging)
                try fm.copyItem(at: mountedApp, to: staging)
                // Strip quarantine so the updated app launches without a
                // Gatekeeper prompt (we verified the checksum ourselves).
                run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
                try fm.removeItem(at: destination)
                if finalURL != destination {
                    try? fm.removeItem(at: finalURL)
                }
                try fm.moveItem(at: staging, to: finalURL)
                installedURL = finalURL
                swapped = true
            } catch {
                try? fm.removeItem(at: staging)
            }
        }

        run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])

        guard swapped else {
            fallbackToManual(dmg: dmg, message: "Couldn't replace the app automatically.")
            return
        }

        try? fm.removeItem(at: workDir)

        let relaunchURL = installedURL
        DispatchQueue.main.async {
            self.isInstalling = false
            self.statusMessage = "Installed — relaunching…"
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(relaunchURL.path)\""]
            try? relaunch.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Last resort: hand the DMG to the user the old way.
    private func fallbackToManual(dmg: URL, message: String) {
        let fm = FileManager.default
        var openURL = dmg
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let dest = downloads.appendingPathComponent(dmgURL?.lastPathComponent ?? "NetPulse.dmg")
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: dmg, to: dest)) != nil {
                openURL = dest
            }
        }
        NSWorkspace.shared.open(openURL)
        finishInstall(message: message + " Drag the app to Applications to finish.")
    }

    private func finishInstall(message: String?) {
        DispatchQueue.main.async {
            self.isInstalling = false
            if let message { self.statusMessage = message }
        }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
