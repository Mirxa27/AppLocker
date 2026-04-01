// Sources/AppLocker/iOS/ScreenPrivacy/iOSScreenPrivacyManager.swift
#if os(iOS)
import UIKit
import Combine
import SwiftUI

@MainActor
class iOSScreenPrivacyManager: ObservableObject {
    static let shared = iOSScreenPrivacyManager()

    @Published var isScreenshotProtectionEnabled: Bool = false {
        didSet { userDefaults.set(isScreenshotProtectionEnabled, forKey: screenshotKey) }
    }
    @Published var isRecordingDetectionEnabled: Bool = true {
        didSet { userDefaults.set(isRecordingDetectionEnabled, forKey: recordingKey) }
    }
    @Published var autoLockOnRecording: Bool = true {
        didSet { userDefaults.set(autoLockOnRecording, forKey: autoLockKey) }
    }
    @Published var hideContentOnBackground: Bool = true {
        didSet { userDefaults.set(hideContentOnBackground, forKey: hideBgKey) }
    }
    @Published var isScreenBeingRecorded: Bool = false
    @Published var blurViewTag: Int = 99998
    @Published var screenshotDetected: Bool = false
    @Published var recentScreenshots: [Date] = []

    private let userDefaults = UserDefaults.standard
    private let screenshotKey = "com.applocker.ios.screenPrivacy.screenshot"
    private let recordingKey = "com.applocker.ios.screenPrivacy.recording"
    private let autoLockKey = "com.applocker.ios.screenPrivacy.autoLock"
    private let hideBgKey = "com.applocker.ios.screenPrivacy.hideBg"
    private let historyKey = "com.applocker.ios.screenPrivacy.history"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadSettings()
        loadHistory()
        setupObservers()
        isScreenBeingRecorded = UIScreen.main.isCaptured
    }

    // MARK: - Observers

    private func setupObservers() {
        // Screen capture detection
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCaptureChange()
                }
            }
            .store(in: &cancellables)

        // Screenshot detection (iOS 11+)
        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenshotDetected()
                }
            }
            .store(in: &cancellables)

        // App background handling
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppForeground()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Capture

    private func handleCaptureChange() {
        isScreenBeingRecorded = UIScreen.main.isCaptured

        if isScreenBeingRecorded && isRecordingDetectionEnabled {
            if autoLockOnRecording {
                AppProtectionManager.shared.lock()
            }
        }
    }

    private func handleScreenshotDetected() {
        screenshotDetected = true
        recentScreenshots.insert(Date(), at: 0)
        if recentScreenshots.count > 20 {
            recentScreenshots = Array(recentScreenshots.prefix(20))
        }
        saveHistory()

        // Reset the flag after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            screenshotDetected = false
        }
    }

    // MARK: - Background Protection

    private func handleAppBackground() {
        guard hideContentOnBackground else { return }
        addPrivacyOverlay()
    }

    private func handleAppForeground() {
        removePrivacyOverlay()
    }

    func addPrivacyOverlay() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }

        if window.viewWithTag(blurViewTag) != nil { return }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.tag = blurViewTag

        let label = UILabel()
        label.text = "AppLocker Protected"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: blur.contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor)
        ])

        window.addSubview(blur)
    }

    func removePrivacyOverlay() {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?
            .viewWithTag(blurViewTag)?.removeFromSuperview()
    }

    // MARK: - Screenshot Protection

    func applyScreenshotProtection(to view: UIView) {
        guard isScreenshotProtectionEnabled else { return }
        // On iOS, we cannot truly prevent screenshots, but we can:
        // 1. Detect them via the notification
        // 2. Hide content when screenshot is detected
        // 3. Use secure text entry fields for sensitive data
    }

    // MARK: - Statistics

    var screenshotCountThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recentScreenshots.filter { $0 >= cutoff }.count
    }

    var lastScreenshotDate: Date? {
        recentScreenshots.first
    }

    // MARK: - History

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentScreenshots) {
            userDefaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let dates = try? JSONDecoder().decode([Date].self, from: data) else {
            return
        }
        recentScreenshots = dates
    }

    func clearHistory() {
        recentScreenshots.removeAll()
        saveHistory()
    }

    // MARK: - Settings

    private func loadSettings() {
        isScreenshotProtectionEnabled = userDefaults.bool(forKey: screenshotKey)
        if userDefaults.object(forKey: recordingKey) != nil {
            isRecordingDetectionEnabled = userDefaults.bool(forKey: recordingKey)
        }
        if userDefaults.object(forKey: autoLockKey) != nil {
            autoLockOnRecording = userDefaults.bool(forKey: autoLockKey)
        }
        if userDefaults.object(forKey: hideBgKey) != nil {
            hideContentOnBackground = userDefaults.bool(forKey: hideBgKey)
        }
    }
}
#endif
