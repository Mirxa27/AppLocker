#if os(iOS)
import SwiftUI
import LocalAuthentication

struct iOSSettingsView: View {
    @ObservedObject private var protection = AppProtectionManager.shared
    @ObservedObject private var ck         = CloudKitManager.shared
    @State private var showChangePIN = false
    @State private var newPIN        = ""
    @State private var confirmPIN    = ""
    @State private var pinError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("App Protection") {
                    HStack {
                        Label("Face ID / Touch ID", systemImage: "faceid")
                        Spacer()
                        Image(systemName: biometricAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(biometricAvailable ? .green : .red)
                    }
                    Button(protection.isPINSet() ? "Change PIN" : "Set PIN") {
                        newPIN = ""; confirmPIN = ""; pinError = nil; showChangePIN = true
                    }
                }

                Section("Security Status") {
                    Label(
                        protection.isJailbroken ? "Jailbreak detected!" : "Device integrity OK",
                        systemImage: protection.isJailbroken
                            ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                    )
                    .foregroundColor(protection.isJailbroken ? .red : .green)

                    Label(
                        ck.iCloudAvailable ? "iCloud connected" : "iCloud not available",
                        systemImage: ck.iCloudAvailable ? "icloud.fill" : "icloud.slash"
                    )
                    .foregroundColor(ck.iCloudAvailable ? .green : .orange)
                }

                Section("Session") {
                    Button(role: .destructive) { protection.lock() } label: {
                        Label("Lock App Now", systemImage: "lock.fill")
                    }
                }

                Section("About") {
                    LabeledContent("Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Platform", value: "iOS Companion")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showChangePIN) {
                NavigationStack {
                    Form {
                        Section("New PIN (4–6 digits)") {
                            SecureField("New PIN", text: $newPIN).keyboardType(.numberPad)
                            SecureField("Confirm PIN", text: $confirmPIN).keyboardType(.numberPad)
                        }
                        if let err = pinError { Text(err).foregroundColor(.red) }
                    }
                    .navigationTitle(protection.isPINSet() ? "Change PIN" : "Set PIN")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showChangePIN = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard newPIN == confirmPIN else { pinError = "PINs don't match"; return }
                                guard newPIN.count >= 4 else { pinError = "Must be 4+ digits"; return }
                                if protection.setPIN(newPIN) { showChangePIN = false }
                                else { pinError = protection.authError }
                            }
                        }
                    }
                }
            }
        }
    }

    private var biometricAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
#endif
