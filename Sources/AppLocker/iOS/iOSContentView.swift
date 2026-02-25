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
                    .overlay(protection.isScreenRecording ? AnyView(ScreenRecordingOverlay()) : AnyView(EmptyView()))
            }
        }
        .animation(.easeInOut, value: protection.isAppLocked)
        .task {
            if !protection.isPINSet() {
                _ = await protection.authenticateBiometric()
            }
        }
    }
}

// MARK: - Lock Screen

struct iOSLockScreen: View {
    @ObservedObject private var protection = AppProtectionManager.shared
    @State private var pin = ""
    @State private var showPINField = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundColor(.blue)
            Text("AppLocker")
                .font(.largeTitle.bold())
            Text("Authenticate to continue")
                .foregroundColor(.secondary)

            if showPINField {
                SecureField("Enter PIN", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 200)
                    .onSubmit { protection.verifyPIN(pin); pin = "" }
                if let err = protection.authError {
                    Text(err).foregroundColor(.red).font(.caption)
                }
                Button("Verify PIN") { protection.verifyPIN(pin); pin = "" }
                    .buttonStyle(.borderedProminent)
            }

            Button(action: {
                Task {
                    let ok = await protection.authenticateBiometric()
                    if !ok { showPINField = true }
                }
            }) {
                Label("Use Face ID / Touch ID", systemImage: "faceid")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
        .task { _ = await protection.authenticateBiometric() }
    }
}

// MARK: - Main Tabs

struct iOSMainTabs: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.medium") }
            AlertsView()
                .tabItem { Label("Alerts",    systemImage: "bell.badge.fill") }
            RemoteControlView()
                .tabItem { Label("Remote",    systemImage: "tv.remote.fill") }
            iOSSecureNotesView()
                .tabItem { Label("Notes",     systemImage: "note.text") }
            iOSIntruderPhotosView()
                .tabItem { Label("Intruder",  systemImage: "eye.trianglebadge.exclamationmark") }
            iOSSettingsView()
                .tabItem { Label("Settings",  systemImage: "gear") }
        }
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
