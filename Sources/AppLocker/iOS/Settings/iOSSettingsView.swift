#if os(iOS)
import SwiftUI
import LocalAuthentication

struct iOSSettingsView: View {
    @ObservedObject private var protection = AppProtectionManager.shared
    @ObservedObject private var ck         = CloudKitManager.shared
    @State private var showChangePIN = false
    @State private var currentPIN    = ""
    @State private var newPIN        = ""
    @State private var confirmPIN    = ""
    @State private var pinError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    protectionCard
                    securityStatusCard
                    appLockCard
                    privacyCard
                    cloudCard
                    sessionCard
                    aboutCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showChangePIN) {
                NavigationStack {
                    Form {
                        Section("New PIN (4-6 digits)") {
                            if protection.isPINSet() {
                                SecureField("Current PIN", text: $currentPIN)
                                    .keyboardType(.numberPad)
                            }
                            SecureField("New PIN", text: $newPIN)
                                .keyboardType(.numberPad)
                            SecureField("Confirm PIN", text: $confirmPIN)
                                .keyboardType(.numberPad)
                        }
                        if let err = pinError {
                            Text(err)
                                .foregroundStyle(AppDesign.danger)
                        }
                    }
                    .navigationTitle(protection.isPINSet() ? "Change PIN" : "Set PIN")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showChangePIN = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard newPIN == confirmPIN else {
                                    pinError = "PINs don't match"
                                    return
                                }
                                guard (4...6).contains(newPIN.count) else {
                                    pinError = "PIN must be 4 to 6 digits"
                                    return
                                }

                                if protection.isPINSet() {
                                    let result = protection.changePIN(currentPIN: currentPIN, newPIN: newPIN)
                                    if result.success {
                                        currentPIN = ""
                                        newPIN = ""
                                        confirmPIN = ""
                                        pinError = nil
                                        showChangePIN = false
                                    } else {
                                        pinError = result.error
                                    }
                                } else if protection.setPIN(newPIN) {
                                    currentPIN = ""
                                    newPIN = ""
                                    confirmPIN = ""
                                    pinError = nil
                                    showChangePIN = false
                                } else {
                                    pinError = protection.authError
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await ck.checkiCloudStatus()
        }
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Protection")
                .font(.headline)

            HStack {
                Label("Face ID / Touch ID", systemImage: "faceid")
                Spacer()
                Image(systemName: biometricAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(biometricAvailable ? AppDesign.success : AppDesign.danger)
            }

            Button(protection.isPINSet() ? "Change PIN" : "Set PIN") {
                currentPIN = ""
                newPIN = ""
                confirmPIN = ""
                pinError = nil
                showChangePIN = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.accent)
        }
        .appSurface()
    }

    private var securityStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Security Status")
                .font(.headline)

            statusRow(
                label: protection.isJailbroken ? "Jailbreak detected" : "Device integrity OK",
                icon: protection.isJailbroken ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                color: protection.isJailbroken ? AppDesign.danger : AppDesign.success
            )
            statusRow(
                label: protection.isPINSet() ? "PIN protection enabled" : "PIN protection disabled",
                icon: protection.isPINSet() ? "lock.fill" : "lock.slash",
                color: protection.isPINSet() ? AppDesign.success : AppDesign.warning
            )
            statusRow(
                label: ck.iCloudAvailable ? "iCloud connected" : "iCloud unavailable",
                icon: ck.iCloudAvailable ? "icloud.fill" : "icloud.slash",
                color: ck.iCloudAvailable ? AppDesign.success : AppDesign.warning
            )

            if let cloudError = ck.lastSyncError, !cloudError.isEmpty {
                Label(cloudError, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(AppDesign.warning)
            }
        }
        .appSurface()
    }

    private var appLockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Lock")
                .font(.headline)

            let lockManager = iOSAppLockManager.shared

            HStack {
                Label("Locked Apps", systemImage: "lock.fill")
                Spacer()
                Text("\(lockManager.lockedAppCount)")
                    .font(.headline)
                    .foregroundStyle(AppDesign.accent)
            }

            HStack {
                Label("Biometric Unlock", systemImage: "faceid")
                Spacer()
                AppStatusBadge(
                    text: lockManager.useBiometricForUnlock ? "On" : "Off",
                    color: lockManager.useBiometricForUnlock ? AppDesign.success : .secondary
                )
            }

            HStack {
                Label("Auto-Lock on Background", systemImage: "arrow.down.app.fill")
                Spacer()
                AppStatusBadge(
                    text: lockManager.autoLockOnBackground ? "On" : "Off",
                    color: lockManager.autoLockOnBackground ? AppDesign.success : .secondary
                )
            }
        }
        .appSurface()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy & Protection")
                .font(.headline)

            let clipboard = iOSClipboardGuard.shared
            let screenPrivacy = iOSScreenPrivacyManager.shared

            HStack {
                Label("Clipboard Guard", systemImage: "doc.on.clipboard")
                Spacer()
                AppStatusBadge(
                    text: clipboard.isEnabled ? "Active" : "Inactive",
                    color: clipboard.isEnabled ? AppDesign.success : .secondary
                )
            }

            HStack {
                Label("Screen Recording Detection", systemImage: "eye.trianglebadge.exclamationmark")
                Spacer()
                AppStatusBadge(
                    text: screenPrivacy.isRecordingDetectionEnabled ? "On" : "Off",
                    color: screenPrivacy.isRecordingDetectionEnabled ? AppDesign.success : .secondary
                )
            }

            HStack {
                Label("Hide Content on Background", systemImage: "eye.slash.fill")
                Spacer()
                AppStatusBadge(
                    text: screenPrivacy.hideContentOnBackground ? "On" : "Off",
                    color: screenPrivacy.hideContentOnBackground ? AppDesign.success : .secondary
                )
            }
        }
        .appSurface()
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloud Sync")
                .font(.headline)

            Button {
                Task {
                    await ck.checkiCloudStatus()
                }
            } label: {
                Label("Refresh iCloud Status", systemImage: "arrow.clockwise.icloud")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                CloudKitManager.shared.setupPushSubscriptions()
            } label: {
                Label("Repair Push Subscriptions", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .appSurface()
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session")
                .font(.headline)

            Button(role: .destructive) {
                protection.lock()
            } label: {
                Label("Lock App Now", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.danger)
        }
        .appSurface()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.headline)

            LabeledContent(
                "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
            )
            LabeledContent("Platform", value: "iOS Companion")
        }
        .appSurface()
    }

    private func statusRow(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
#endif
