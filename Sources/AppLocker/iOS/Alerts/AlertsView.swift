#if os(iOS)
import SwiftUI
import CloudKit

enum AlertEventType: String, CaseIterable, Identifiable {
    var id: Self { self }
    case all      = "All"
    case blocked  = "Blocked"
    case failed   = "Failed Auth"
}

@MainActor
class AlertsViewModel: ObservableObject {
    @Published var records: [CKRecord] = []
    @Published var filter   = AlertEventType.all
    @Published var isLoading = false

    var filtered: [CKRecord] {
        switch filter {
        case .all:     return records
        case .blocked: return records.filter { $0.recordType == "BlockedAppEvent" }
        case .failed:  return records.filter { $0.recordType == "FailedAuthEvent" }
        }
    }

    func refresh() {
        isLoading = true
        Task {
            async let blocked = CloudKitManager.shared.fetchBlockedEvents()
            async let failed  = CloudKitManager.shared.fetchFailedAuthEvents()
            let all = ((try? await blocked) ?? []) + ((try? await failed) ?? [])
            records = all.sorted {
                ($0["timestamp"] as? Date ?? .distantPast) >
                ($1["timestamp"] as? Date ?? .distantPast)
            }
            isLoading = false
        }
    }
}

struct AlertsView: View {
    @StateObject private var vm = AlertsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $vm.filter) {
                    ForEach(AlertEventType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented).padding(.horizontal)

                List(vm.filtered, id: \.recordID) { rec in AlertRowView(record: rec) }
                    .overlay(vm.isLoading ? ProgressView() : nil)
                    .overlay(
                        !vm.isLoading && vm.filtered.isEmpty
                            ? Text("No alerts").foregroundColor(.secondary) : nil
                    )
            }
            .navigationTitle("Alerts")
            .toolbar {
                Button(action: vm.refresh) { Image(systemName: "arrow.clockwise") }
            }
            .refreshable { vm.refresh() }
            .task { vm.refresh() }
        }
    }
}

struct AlertRowView: View {
    let record: CKRecord
    var isFailed: Bool { record.recordType == "FailedAuthEvent" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .foregroundColor(isFailed ? .red : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(record["appName"] as? String ?? "Unknown").font(.headline)
                Text(record["deviceName"] as? String ?? "")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let ts = record["timestamp"] as? Date {
                Text(ts.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
