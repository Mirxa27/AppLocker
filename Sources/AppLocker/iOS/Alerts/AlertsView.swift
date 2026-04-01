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
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Filter")
                                .font(.headline)
                            Spacer()
                            AppStatusBadge(
                                text: "\(filtered.count)",
                                color: filter == .failed ? AppDesign.danger : AppDesign.accent
                            )
                        }

                        Picker("Filter", selection: $filter) {
                            ForEach(AlertFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .appSurface()

                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("No Alerts")
                                .font(.title3.weight(.semibold))
                            Text("Alerts appear here when your Mac blocks apps or detects failed unlock attempts.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .appSurface()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { alert in
                                AlertRecordRow(alert: alert)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        kv.decodeAllKeys()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                if !kv.alertHistory.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            kv.clearHistory()
                        }
                    }
                }
            }
            .refreshable {
                kv.decodeAllKeys()
            }
        }
    }
}

struct AlertRecordRow: View {
    let alert: AlertRecord

    private var isFailed: Bool {
        alert.type.contains("fail")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .foregroundStyle(isFailed ? AppDesign.danger : AppDesign.warning)
                .font(.title3)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.appName)
                    .font(.headline)
                Text(alert.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                AppStatusBadge(
                    text: isFailed ? "Failed" : "Blocked",
                    color: isFailed ? AppDesign.danger : AppDesign.warning
                )
                Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .appSurface(padding: 14, cornerRadius: 14)
    }
}
#endif
