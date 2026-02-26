// Sources/AppLocker/iOS/Dashboard/DashboardView.swift
#if os(iOS)
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var kv         = KVStoreManager.shared
    @ObservedObject private var protection = AppProtectionManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Mac Device") {
                    if let device = kv.lastMacDevice {
                        HStack {
                            Image(systemName: "desktopcomputer").foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device).font(.headline)
                                if let sync = kv.lastSyncTime {
                                    Text("Last seen \(sync.formatted(.relative(presentation: .named)))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        HStack {
                            Image(systemName: "lock.app.dashed").foregroundColor(.orange)
                            Text("\(kv.lockedApps.count) app\(kv.lockedApps.count == 1 ? "" : "s") locked")
                                .font(.subheadline)
                        }
                    } else {
                        Label("No Mac connected — open AppLocker on your Mac",
                              systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Recent Blocks") {
                    let recent = Array(kv.alertHistory.filter { $0.type.contains("block") }.prefix(5))
                    if recent.isEmpty {
                        Text("No recent blocks").foregroundColor(.secondary).font(.caption)
                    } else {
                        ForEach(recent) { alert in
                            HStack {
                                Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.appName).font(.subheadline)
                                    Text(alert.timestamp.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("iOS Security") {
                    Label(
                        protection.isJailbroken ? "Jailbreak detected!" : "Device integrity OK",
                        systemImage: protection.isJailbroken ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                    ).foregroundColor(protection.isJailbroken ? .red : .green)

                    Label(
                        protection.isPINSet() ? "PIN protection enabled" : "No PIN set",
                        systemImage: protection.isPINSet() ? "lock.fill" : "lock.slash"
                    ).foregroundColor(protection.isPINSet() ? .green : .orange)

                    Label(
                        protection.isScreenRecording ? "Screen recording active!" : "Screen not recorded",
                        systemImage: protection.isScreenRecording ? "eye.trianglebadge.exclamationmark" : "eye.slash"
                    ).foregroundColor(protection.isScreenRecording ? .red : .secondary)
                }
            }
            .navigationTitle("Dashboard")
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
