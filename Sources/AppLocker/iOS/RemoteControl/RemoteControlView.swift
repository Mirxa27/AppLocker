#if os(iOS)
import SwiftUI
import CloudKit
import LocalAuthentication

@MainActor
class RemoteControlViewModel: ObservableObject {
    @Published var deviceRecords: [CKRecord] = []
    @Published var selectedDevice: CKRecord?
    @Published var lockedApps:  [LockedAppInfo] = []
    @Published var isLoading    = false
    @Published var statusMessage: String?

    func loadDevices() {
        isLoading = true
        Task {
            deviceRecords = (try? await CloudKitManager.shared.fetchLockedAppLists()) ?? []
            if selectedDevice == nil { selectedDevice = deviceRecords.first }
            await loadAppsForSelectedDevice()
            isLoading = false
        }
    }

    func loadAppsForSelectedDevice() async {
        guard let rec = selectedDevice,
              let asset = rec["apps"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([LockedAppInfo].self, from: data)
        else { lockedApps = []; return }
        lockedApps = apps
    }

    func sendCommand(_ action: RemoteCommand.Action, bundleID: String? = nil) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            statusMessage = "Biometrics required to send commands"; return false
        }
        do {
            _ = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                              localizedReason: "Confirm remote command")
        } catch { statusMessage = error.localizedDescription; return false }
        NotificationManager.shared.sendRemoteCommand(action, bundleID: bundleID)
        statusMessage = "Command sent to Mac"
        return true
    }
}

struct RemoteControlView: View {
    @StateObject private var vm = RemoteControlViewModel()
    @State private var searchText = ""

    var filteredApps: [LockedAppInfo] {
        searchText.isEmpty ? vm.lockedApps
            : vm.lockedApps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.deviceRecords.count > 1 {
                    Section("Mac Device") {
                        Picker("Device", selection: $vm.selectedDevice) {
                            ForEach(vm.deviceRecords, id: \.recordID) { rec in
                                Text(rec["deviceName"] as? String ?? "Mac").tag(Optional(rec))
                            }
                        }
                        .onChange(of: vm.selectedDevice) { _ in
                            Task { await vm.loadAppsForSelectedDevice() }
                        }
                    }
                }

                Section("Global") {
                    Button(role: .destructive) {
                        Task { _ = await vm.sendCommand(.lockAll) }
                    } label: {
                        Label("Lock All Apps", systemImage: "lock.fill")
                    }
                    Button {
                        Task { _ = await vm.sendCommand(.unlockAll) }
                    } label: {
                        Label("Unlock All Apps", systemImage: "lock.open.fill").foregroundColor(.green)
                    }
                }

                Section("Locked Apps (\(vm.lockedApps.count))") {
                    if vm.lockedApps.isEmpty {
                        Text("No locked apps — open AppLocker on Mac first")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(filteredApps) { app in
                            HStack {
                                VStack(alignment: .leading) {
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
                    Section { Text(msg).foregroundColor(.green).font(.caption) }
                }
            }
            .searchable(text: $searchText, prompt: "Search locked apps")
            .navigationTitle("Remote Control")
            .refreshable { vm.loadDevices() }
            .task { vm.loadDevices() }
            .overlay(vm.isLoading ? ProgressView() : nil)
        }
    }
}
#endif
