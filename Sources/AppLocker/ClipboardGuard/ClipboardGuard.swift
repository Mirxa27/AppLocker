// Sources/AppLocker/ClipboardGuard/ClipboardGuard.swift
#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
class ClipboardGuard: ObservableObject {
    static let shared = ClipboardGuard()

    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            isEnabled ? startMonitoring() : stopMonitoring()
        }
    }
    @Published var clearDelaySeconds: Int = 30 {
        didSet { UserDefaults.standard.set(clearDelaySeconds, forKey: delayKey) }
    }
    @Published var recentEvents: [ClipboardEvent] = []
    @Published var secondsUntilClear: Int = 0

    private var monitorTimer: AnyCancellable?
    private var clearWorkItem: DispatchWorkItem?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let enabledKey = "com.applocker.clipboardGuard.enabled"
    private let delayKey = "com.applocker.clipboardGuard.delay"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let savedDelay = UserDefaults.standard.integer(forKey: delayKey)
        clearDelaySeconds = savedDelay > 0 ? savedDelay : 30
        if isEnabled { startMonitoring() }
    }

    private func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        monitorTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.tick() }
    }

    private func stopMonitoring() {
        monitorTimer?.cancel(); monitorTimer = nil
        clearWorkItem?.cancel(); clearWorkItem = nil
        secondsUntilClear = 0
    }

    private func tick() {
        let current = NSPasteboard.general.changeCount
        if current != lastChangeCount {
            lastChangeCount = current
            let charCount = NSPasteboard.general.string(forType: .string)?.count ?? 0
            let event = ClipboardEvent(timestamp: Date(), estimatedCharCount: charCount)
            recentEvents.insert(event, at: 0)
            if recentEvents.count > 20 { recentEvents = Array(recentEvents.prefix(20)) }
            scheduleClear()
        }
        if secondsUntilClear > 0 { secondsUntilClear -= 1 }
    }

    private func scheduleClear() {
        clearWorkItem?.cancel()
        secondsUntilClear = clearDelaySeconds
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents()
            self.secondsUntilClear = 0
            self.recentEvents.insert(ClipboardEvent(timestamp: Date(), estimatedCharCount: 0), at: 0)
            if self.recentEvents.count > 20 { self.recentEvents = Array(self.recentEvents.prefix(20)) }
        }
        clearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(clearDelaySeconds), execute: item)
    }

    func clearNow() {
        clearWorkItem?.cancel()
        NSPasteboard.general.clearContents()
        secondsUntilClear = 0
    }
}
#endif
