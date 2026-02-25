#if os(iOS)
import SwiftUI
import CloudKit

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var deviceRecords: [CKRecord] = []
    @Published var recentAlerts:  [CKRecord] = []
    @Published var isLoading = false
    @Published var error: String?

    func refresh() {
        isLoading = true; error = nil
        Task {
            do {
                async let lists  = CloudKitManager.shared.fetchLockedAppLists()
                async let alerts = CloudKitManager.shared.fetchBlockedEvents(limit: 5)
                deviceRecords = try await lists
                recentAlerts  = try await alerts
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @ObservedObject private var ck = CloudKitManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("iCloud Status") {
                    Label(
                        ck.iCloudAvailable ? "Connected" : "Not signed in to iCloud",
                        systemImage: ck.iCloudAvailable ? "icloud.fill" : "icloud.slash"
                    )
                    .foregroundColor(ck.iCloudAvailable ? .green : .orange)
                }

                Section("Mac Devices") {
                    if vm.deviceRecords.isEmpty {
                        Text("No Mac found — open AppLocker on your Mac first")
                            .foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(vm.deviceRecords, id: \.recordID) { rec in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(rec["deviceName"] as? String ?? "Mac",
                                      systemImage: "desktopcomputer")
                                    .font(.headline)
                                if let date = rec["updatedAt"] as? Date {
                                    Text("Synced \(date.formatted(.relative(presentation: .named)))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Recent Blocks") {
                    if vm.recentAlerts.isEmpty {
                        Text("No recent events").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(vm.recentAlerts, id: \.recordID) { rec in
                            HStack {
                                Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text(rec["appName"] as? String ?? "Unknown")
                                        .font(.subheadline)
                                    if let ts = rec["timestamp"] as? Date {
                                        Text(ts.formatted(.relative(presentation: .named)))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let err = vm.error {
                    Section { Text(err).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Dashboard")
            .refreshable { vm.refresh() }
            .task { vm.refresh() }
            .overlay(vm.isLoading ? ProgressView() : nil)
        }
    }
}
#endif
