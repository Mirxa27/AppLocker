// Sources/AppLocker/Shared/InactivityMonitor.swift
#if os(macOS)
import AppKit

@MainActor
final class InactivityMonitor {
    static let shared = InactivityMonitor()
    private let timeoutKey = "com.applocker.inactivityTimeout"

    var timeout: TimeInterval {
        didSet {
            UserDefaults.standard.set(timeout, forKey: timeoutKey)
            if isRunning { start() }
        }
    }

    private var timer: Timer?
    private var eventMonitor: Any?
    private(set) var isRunning = false

    private init() {
        let saved = UserDefaults.standard.double(forKey: "com.applocker.inactivityTimeout")
        timeout = saved > 0 ? saved : 600
    }

    func start() {
        stop()
        isRunning = true
        resetTimer()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetTimer() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate(); timer = nil
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func resetTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lock() }
        }
    }

    private func lock() {
        guard AuthenticationManager.shared.isAuthenticated else { return }
        AuthenticationManager.shared.logout()
        AppMonitor.shared.temporarilyUnlockedApps.removeAll()
        AppMonitor.shared.addLog("Auto-locked: inactivity timeout (\(Int(timeout / 60)) min)")
    }
}
#endif
