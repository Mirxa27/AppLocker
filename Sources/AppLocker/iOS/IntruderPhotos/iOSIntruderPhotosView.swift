#if os(iOS)
import SwiftUI
import UIKit

private struct IntruderEvidence: Identifiable {
    let id: String
    let appName: String
    let bundleID: String
    let deviceName: String
    let timestamp: Date
    let imageData: Data?
    let source: String

    var hasPhoto: Bool { imageData != nil }
}

private enum IntruderFilter: String, CaseIterable, Identifiable {
    var id: Self { self }

    case all = "All"
    case photo = "With Photo"
    case alertsOnly = "Alerts Only"
}

@MainActor
private final class iOSIntruderPhotosViewModel: ObservableObject {
    @Published var entries: [IntruderEvidence] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil

        let fallbackAlerts = loadFallbackAlerts()
        var cloudEntries: [IntruderEvidence] = []

        do {
            await CloudKitManager.shared.checkiCloudStatus()
            if CloudKitManager.shared.iCloudAvailable {
                cloudEntries = try await loadCloudKitEntries()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        entries = merge(cloudEntries: cloudEntries, fallbackAlerts: fallbackAlerts)

        if entries.isEmpty, let cloudError = CloudKitManager.shared.lastSyncError {
            errorMessage = cloudError
        }
    }

    private func loadCloudKitEntries() async throws -> [IntruderEvidence] {
        let records = try await CloudKitManager.shared.fetchFailedAuthEvents(limit: 80)
        var items: [IntruderEvidence] = []
        items.reserveCapacity(records.count)

        for record in records {
            let appName = (record["appName"] as? String) ?? "AppLocker"
            let bundleID = (record["bundleID"] as? String) ?? "com.applocker.unknown"
            let deviceName = (record["deviceName"] as? String) ?? "Unknown Device"
            let timestamp = (record["timestamp"] as? Date) ?? record.creationDate ?? Date.distantPast
            let imageData = await CloudKitManager.shared.loadAssetData(from: record)

            items.append(
                IntruderEvidence(
                    id: "ck-\(record.recordID.recordName)",
                    appName: appName,
                    bundleID: bundleID,
                    deviceName: deviceName,
                    timestamp: timestamp,
                    imageData: imageData,
                    source: "CloudKit"
                )
            )
        }

        return items
    }

    private func loadFallbackAlerts() -> [IntruderEvidence] {
        KVStoreManager.shared.alertHistory
            .filter { $0.type.contains("fail") }
            .map {
                IntruderEvidence(
                    id: "kv-\($0.id.uuidString)",
                    appName: $0.appName,
                    bundleID: $0.bundleID,
                    deviceName: $0.deviceName,
                    timestamp: $0.timestamp,
                    imageData: nil,
                    source: "KV Store"
                )
            }
    }

    private func merge(cloudEntries: [IntruderEvidence], fallbackAlerts: [IntruderEvidence]) -> [IntruderEvidence] {
        var merged = cloudEntries

        for fallback in fallbackAlerts {
            let duplicate = cloudEntries.contains {
                $0.appName == fallback.appName &&
                $0.deviceName == fallback.deviceName &&
                abs($0.timestamp.timeIntervalSince1970 - fallback.timestamp.timeIntervalSince1970) < 5
            }
            if !duplicate {
                merged.append(fallback)
            }
        }

        return merged.sorted { $0.timestamp > $1.timestamp }
    }
}

struct iOSIntruderPhotosView: View {
    @StateObject private var vm = iOSIntruderPhotosViewModel()
    @State private var filter: IntruderFilter = .all

    private var filteredEntries: [IntruderEvidence] {
        switch filter {
        case .all:
            return vm.entries
        case .photo:
            return vm.entries.filter(\.hasPhoto)
        case .alertsOnly:
            return vm.entries.filter { !$0.hasPhoto }
        }
    }

    private var photoCount: Int { vm.entries.filter(\.hasPhoto).count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                summaryCard

                Picker("Filter", selection: $filter) {
                    ForEach(IntruderFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                content
            }
            .navigationTitle("Intruder Evidence")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await vm.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await vm.refresh() }
            .refreshable { await vm.refresh() }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Security Evidence")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(photoCount) photo capture\(photoCount == 1 ? "" : "s") • \(vm.entries.count) total event\(vm.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: photoCount > 0 ? "camera.badge.ellipsis" : "eye.trianglebadge.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(photoCount > 0 ? .red : .orange)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        if filteredEntries.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("No Intruder Evidence")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Failed unlock attempts from your Mac will appear here. Photos are shown when CloudKit uploads include camera evidence.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            }
        } else {
            List(filteredEntries) { entry in
                IntruderEvidenceRow(entry: entry)
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct IntruderEvidenceRow: View {
    let entry: IntruderEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData = entry.imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.hasPhoto ? "person.crop.rectangle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .foregroundColor(entry.hasPhoto ? .red : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Failed unlock on \(entry.appName)")
                        .font(.subheadline.weight(.semibold))
                    Text(entry.deviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(entry.source)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
            }
        }
        .padding(.vertical, 6)
    }
}
#endif
