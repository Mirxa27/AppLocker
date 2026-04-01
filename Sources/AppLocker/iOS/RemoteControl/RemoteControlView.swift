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
            statusMessage = "Biometrics required to send commands"
            return false
        }
        do {
            _ = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm remote command"
            )
        } catch {
            statusMessage = error.localizedDescription
            return false
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

    private var filteredApps: [LockedAppInfo] {
        searchText.isEmpty
            ? kv.lockedApps
            : kv.lockedApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    globalCommandCard
                    appsCard

                    if let msg = vm.statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppDesign.success)
                            Text(msg)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .appSurface(padding: 14, cornerRadius: 14)
                    }
                }
                .padding(16)
            }
            .appScreenBackground()
            .searchable(text: $searchText, prompt: "Search locked apps")
            .navigationTitle("Remote Control")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        kv.decodeAllKeys()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                kv.decodeAllKeys()
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connection")
                    .font(.headline)
                Spacer()
                AppStatusBadge(
                    text: kv.lastMacDevice == nil ? "Offline" : "Online",
                    color: kv.lastMacDevice == nil ? AppDesign.warning : AppDesign.success
                )
            }

            if let device = kv.lastMacDevice {
                Text(device)
                    .font(.title3.weight(.semibold))
                if let sync = kv.lastSyncTime {
                    Text("Last seen \(sync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Open AppLocker on your Mac first to enable commands.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .appSurface()
    }

    private var globalCommandCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Commands")
                .font(.headline)

            Button(role: .destructive) {
                Task {
                    _ = await vm.sendCommand(.lockAll)
                }
            } label: {
                Label("Lock All Apps", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppDesign.danger)

            Button {
                Task {
                    _ = await vm.sendCommand(.unlockAll)
                }
            } label: {
                Label("Unlock All Apps", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppDesign.success)
        }
        .appSurface()
    }

    @ViewBuilder
    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Locked Apps")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(kv.lockedApps.count)", color: AppDesign.accent)
            }

            if kv.lockedApps.isEmpty {
                Text(
                    kv.lastMacDevice == nil
                    ? "Connect your Mac to view lock targets."
                    : "No apps are currently locked."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else if filteredApps.isEmpty {
                Text("No apps match your search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredApps) { app in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(app.bundleID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("Unlock") {
                            Task {
                                _ = await vm.sendCommand(.unlockApp, bundleID: app.bundleID)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .appSurface()
    }
}
#endif
