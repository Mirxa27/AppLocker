// Sources/AppLocker/iOS/ClipboardGuard/iOSClipboardGuard.swift
#if os(iOS)
import UIKit
import Combine
import SwiftUI

@MainActor
class iOSClipboardGuard: ObservableObject {
    static let shared = iOSClipboardGuard()

    @Published var isEnabled: Bool = false {
        didSet {
            userDefaults.set(isEnabled, forKey: enabledKey)
            isEnabled ? startMonitoring() : stopMonitoring()
        }
    }
    @Published var clearDelaySeconds: Int = 30 {
        didSet { userDefaults.set(clearDelaySeconds, forKey: delayKey) }
    }
    @Published var recentEvents: [ClipboardEvent] = []
    @Published var secondsUntilClear: Int = 0
    @Published var protectSensitiveData: Bool = true {
        didSet { userDefaults.set(protectSensitiveData, forKey: sensitiveKey) }
    }

    private var monitorTimer: AnyCancellable?
    private var clearWorkItem: DispatchWorkItem?
    private var lastChangeCount: Int = UIPasteboard.general.changeCount
    private let enabledKey = "com.applocker.ios.clipboardGuard.enabled"
    private let delayKey = "com.applocker.ios.clipboardGuard.delay"
    private let sensitiveKey = "com.applocker.ios.clipboardGuard.sensitive"
    private let historyKey = "com.applocker.ios.clipboardGuard.history"
    private let userDefaults = UserDefaults.standard

    private init() {
        isEnabled = userDefaults.bool(forKey: enabledKey)
        let savedDelay = userDefaults.integer(forKey: delayKey)
        clearDelaySeconds = savedDelay > 0 ? savedDelay : 30
        protectSensitiveData = userDefaults.object(forKey: sensitiveKey) as? Bool ?? true
        loadHistory()
        if isEnabled { startMonitoring() }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        lastChangeCount = UIPasteboard.general.changeCount
        monitorTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tick()
                }
            }
    }

    func stopMonitoring() {
        monitorTimer?.cancel()
        monitorTimer = nil
        clearWorkItem?.cancel()
        clearWorkItem = nil
        secondsUntilClear = 0
    }

    private func tick() {
        let current = UIPasteboard.general.changeCount
        if current != lastChangeCount {
            lastChangeCount = current
            let charCount = UIPasteboard.general.string?.count ?? 0
            let containsSensitive = detectSensitiveContent()

            let event = ClipboardEvent(
                timestamp: Date(),
                estimatedCharCount: charCount
            )
            recentEvents.insert(event, at: 0)
            if recentEvents.count > 50 {
                recentEvents = Array(recentEvents.prefix(50))
            }
            saveHistory()

            if protectSensitiveData && containsSensitive {
                scheduleClear(delay: clearDelaySeconds / 2)
            } else {
                scheduleClear()
            }
        }
        if secondsUntilClear > 0 {
            secondsUntilClear -= 1
        }
    }

    // MARK: - Sensitive Content Detection

    private func detectSensitiveContent() -> Bool {
        guard let content = UIPasteboard.general.string else { return false }
        let sensitivePatterns = [
            "\\b\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}\\b",  // Credit card
            "\\b\\d{3}[- ]?\\d{2}[- ]?\\d{4}\\b",               // SSN
            "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b", // Email
            "\\b\\d{10,}\\b",                                    // Phone numbers
            "(?i)password|passwd|secret|token|api.?key"          // Credentials
        ]

        for pattern in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Clear Operations

    private func scheduleClear(delay: Int? = nil) {
        clearWorkItem?.cancel()
        let actualDelay = delay ?? clearDelaySeconds
        secondsUntilClear = actualDelay

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIPasteboard.general.items = []
            self.secondsUntilClear = 0
            let event = ClipboardEvent(timestamp: Date(), estimatedCharCount: 0)
            self.recentEvents.insert(event, at: 0)
            if self.recentEvents.count > 50 {
                self.recentEvents = Array(self.recentEvents.prefix(50))
            }
            self.saveHistory()
        }
        clearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(actualDelay), execute: item)
    }

    func clearNow() {
        clearWorkItem?.cancel()
        UIPasteboard.general.items = []
        secondsUntilClear = 0
    }

    // MARK: - Paste Protection

    func protectClipboard() {
        UIPasteboard.general.setItems([], options: [:])
        let event = ClipboardEvent(timestamp: Date(), estimatedCharCount: 0)
        recentEvents.insert(event, at: 0)
        saveHistory()
    }

    // MARK: - History

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentEvents) {
            userDefaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let events = try? JSONDecoder().decode([ClipboardEvent].self, from: data) else {
            return
        }
        recentEvents = events
    }

    func clearHistory() {
        recentEvents.removeAll()
        saveHistory()
    }
}
#endif
