// Sources/AppLocker/iOS/Alerts/AlertsView.swift
#if os(iOS)
import SwiftUI

enum AlertFilter: String, CaseIterable, Identifiable {
    var id: Self { self }
    case all     = "All"
    case blocked = "Blocked"
    case failed  = "Failed Auth"
}

struct AlertsView: View {
    @ObservedObject private var kv = KVStoreManager.shared
    @State private var filter: AlertFilter = .all

    var filtered: [AlertRecord] {
        switch filter {
        case .all:     return kv.alertHistory
        case .blocked: return kv.alertHistory.filter { $0.type.contains("block") }
        case .failed:  return kv.alertHistory.filter { $0.type.contains("fail") }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(AlertFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if filtered.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bell.slash")
                            .font(.system(size: 48)).foregroundColor(.secondary)
                        Text("No Alerts").font(.title2).foregroundColor(.secondary)
                        Text("Alerts appear here when your Mac blocks an app.")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Spacer()
                    }
                } else {
                    List(filtered) { alert in
                        AlertRecordRow(alert: alert)
                    }
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { kv.decodeAllKeys() } label: { Image(systemName: "arrow.clockwise") }
                }
                if !kv.alertHistory.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") { kv.clearHistory() }
                    }
                }
            }
            .refreshable { kv.decodeAllKeys() }
        }
    }
}

struct AlertRecordRow: View {
    let alert: AlertRecord
    var isFailed: Bool { alert.type.contains("fail") }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .foregroundColor(isFailed ? .red : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.appName).font(.headline)
                Text(alert.deviceName).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
#endif
