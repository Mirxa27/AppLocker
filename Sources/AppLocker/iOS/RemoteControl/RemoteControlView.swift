// Sources/AppLocker/iOS/RemoteControl/RemoteControlView.swift
#if os(iOS)
import SwiftUI
import LocalAuthentication

@MainActor
class RemoteControlViewModel: ObservableObject {
    @Published var statusMessage: String?

    func sendCommand(_ action: RemoteCommand.Action, bundleID: String? = nil) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            statusMessage = "Biometrics required to send commands"; return false
        }
        do {
            _ = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                              localizedReason: "Confirm remote command")
        } catch {
            statusMessage = error.localizedDescription; return false
        }
        NotificationManager.shared.sendRemoteCommand(action, bundleID: bundleID)
        statusMessage = "Command sent"
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.statusMessage = nil
        }
        return true
    }
}

struct RemoteControlView: View {
    @ObservedObject private var kv = KVStoreManager.shared
    @StateObject private var vm = RemoteControlViewModel()
    @State private var searchText = ""

    var filteredApps: [LockedAppInfo] {
        searchText.isEmpty ? kv.lockedApps
            : kv.lockedApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Global Commands") {
                    Button(role: .destructive) {
                        Task { _ = await vm.sendCommand(.lockAll) }
                    } label: { Label("Lock All Apps", systemImage: "lock.fill") }

                    Button {
                        Task { _ = await vm.sendCommand(.unlockAll) }
                    } label: {
                        Label("Unlock All Apps", systemImage: "lock.open.fill")
                    }.foregroundColor(.green)
                }

                Section("Locked Apps (\(kv.lockedApps.count))") {
                    if kv.lockedApps.isEmpty {
                        Label(
                            kv.lastMacDevice == nil
                                ? "Open AppLocker on your Mac first"
                                : "No apps currently locked",
                            systemImage: kv.lastMacDevice == nil
                                ? "desktopcomputer.trianglebadge.exclamationmark"
                                : "lock.slash"
                        )
                        .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(filteredApps) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName).font(.subheadline)
                                    Text(app.bundleID).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Unlock") {
                                    Task { _ = await vm.sendCommand(.unlockApp, bundleID: app.bundleID) }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }

                if let msg = vm.statusMessage {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.caption)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search locked apps")
            .navigationTitle("Remote Control")
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
