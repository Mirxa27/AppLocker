#if os(iOS)
import SwiftUI
import LocalAuthentication

// MARK: - Root

struct iOSRootView: View {
    @ObservedObject var protection = AppProtectionManager.shared

    var body: some View {
        Group {
            if protection.isAppLocked {
                iOSLockScreen()
            } else {
                iOSMainTabs()
                    .overlay {
                        if protection.isScreenRecording {
                            ScreenRecordingOverlay()
                        }
                    }
            }
        }
        .tint(AppDesign.accent)
        .animation(.easeInOut, value: protection.isAppLocked)
        .task {
            #if targetEnvironment(simulator)
            // On simulator, skip authentication for testing
            if !protection.isPINSet() {
                protection.isAppLocked = false
            }
            #else
            if !protection.isPINSet() {
                _ = await protection.authenticateBiometric()
            }
            #endif
        }
    }
}

// MARK: - Lock Screen

struct iOSLockScreen: View {
    @ObservedObject private var protection = AppProtectionManager.shared
    @State private var pin = ""
    @State private var showPINField = false

    var body: some View {
        ZStack {
            AppDesign.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 92)
                        .background(
                            LinearGradient(
                                colors: [AppDesign.accent, AppDesign.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        }

                    Text("AppLocker")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Authenticate to continue")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                VStack(spacing: 14) {
                    if showPINField {
                        SecureField("Enter PIN", text: $pin)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .onSubmit {
                                _ = protection.verifyPIN(pin)
                                pin = ""
                            }

                        if let err = protection.authError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(AppDesign.danger)
                        }

                        Button("Verify PIN") {
                            _ = protection.verifyPIN(pin)
                            pin = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppDesign.accent)
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        Task {
                            let ok = await protection.authenticateBiometric()
                            if !ok {
                                showPINField = true
                            }
                        }
                    } label: {
                        Label("Use Face ID / Touch ID", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .appSurface(padding: 18, cornerRadius: 18)
                .frame(maxWidth: 360)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task {
            let ok = await protection.authenticateBiometric()
            if !ok {
                showPINField = true
            }
        }
    }
}

// MARK: - Main Tabs

struct iOSMainTabs: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.medium")
                }
                .tag(0)

            iOSAppLockingView()
                .tabItem {
                    Label("Lock", systemImage: "lock.fill")
                }
                .tag(1)

            iOSFocusModeView()
                .tabItem {
                    Label("Focus", systemImage: "timer")
                }
                .tag(2)

            MoreFeaturesView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(3)

            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
        .tint(AppDesign.accent)
    }
}

// MARK: - More Features View

struct MoreFeaturesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    featureCard(
                        title: "App Hiding",
                        description: "Hide apps from your Home Screen",
                        icon: "eye.slash.fill",
                        color: AppDesign.warning,
                        destination: AnyView(iOSAppHidingView())
                    )

                    featureCard(
                        title: "File Locker",
                        description: "Encrypt and protect files",
                        icon: "lock.doc.fill",
                        color: AppDesign.accent,
                        destination: AnyView(iOSFileLockerView())
                    )

                    featureCard(
                        title: "Clipboard Guard",
                        description: "Auto-clear clipboard after delay",
                        icon: "doc.on.clipboard.fill",
                        color: AppDesign.success,
                        destination: AnyView(iOSClipboardGuardView())
                    )

                    featureCard(
                        title: "Screen Privacy",
                        description: "Screenshot and recording protection",
                        icon: "eye.trianglebadge.exclamationmark",
                        color: AppDesign.danger,
                        destination: AnyView(iOSScreenPrivacyView())
                    )

                    featureCard(
                        title: "Alerts",
                        description: "Security event history",
                        icon: "bell.badge.fill",
                        color: AppDesign.warning,
                        destination: AnyView(AlertsView())
                    )

                    featureCard(
                        title: "Remote Control",
                        description: "Control your Mac remotely",
                        icon: "appletvremote.gen4",
                        color: AppDesign.accentSecondary,
                        destination: AnyView(RemoteControlView())
                    )

                    featureCard(
                        title: "Secure Notes",
                        description: "Read encrypted notes from Mac",
                        icon: "note.text",
                        color: .purple,
                        destination: AnyView(iOSSecureNotesView())
                    )

                    featureCard(
                        title: "Intruder Photos",
                        description: "View failed unlock evidence",
                        icon: "camera.fill",
                        color: AppDesign.danger,
                        destination: AnyView(iOSIntruderPhotosView())
                    )
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Features")
        }
    }

    private func featureCard(title: String, description: String, icon: String, color: Color, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppDesign.panelGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen Recording Overlay

struct ScreenRecordingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                Text("Screen recording detected")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("AppLocker content is hidden for your security.")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }.padding()
        }
    }
}
#endif
