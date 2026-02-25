// Sources/AppLocker/ScreenPrivacy/ScreenPrivacyManager.swift
#if os(macOS)
import AppKit
import Combine

@MainActor
class ScreenPrivacyManager: ObservableObject {
    static let shared = ScreenPrivacyManager()

    @Published var detectedRecorders: [String] = []
    @Published var autoLockOnRecording: Bool = false {
        didSet { UserDefaults.standard.set(autoLockOnRecording, forKey: autoLockKey) }
    }
    @Published var isWindowProtected: Bool = false

    private var scanTimer: AnyCancellable?
    private let autoLockKey = "com.applocker.screenPrivacy.autoLock"

    private let knownRecorders: Set<String> = [
        "com.apple.screencapture",
        "com.apple.QuickTimePlayerX",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.elgato.StreamDeck",
        "com.obsproject.obs-studio",
        "net.telestream.screenflow9",
        "com.techsmith.camtasia",
        "com.loom.desktop"
    ]

    private init() {
        autoLockOnRecording = UserDefaults.standard.bool(forKey: autoLockKey)
        startScanning()
    }

    func applyWindowProtection() {
        for window in NSApp.windows {
            window.sharingType = .none
        }
        isWindowProtected = true
    }

    func startScanning() {
        scanTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.scanForRecorders() }
    }

    func scanForRecorders() {
        let running = NSWorkspace.shared.runningApplications
        let detected = running
            .filter { app in
                guard let bid = app.bundleIdentifier else { return false }
                return knownRecorders.contains(bid)
            }
            .compactMap { $0.localizedName ?? $0.bundleIdentifier }

        let changed = Set(detected) != Set(detectedRecorders)
        detectedRecorders = detected

        if !detected.isEmpty && changed && autoLockOnRecording {
            AuthenticationManager.shared.logout()
        }
    }

    func stopScanning() {
        scanTimer?.cancel(); scanTimer = nil
    }
}
#endif
