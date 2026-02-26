// Sources/AppLocker/iOS/IntruderPhotos/iOSIntruderPhotosView.swift
#if os(iOS)
import SwiftUI

struct iOSIntruderPhotosView: View {
    @ObservedObject private var kv = KVStoreManager.shared

    var intruderAlerts: [AlertRecord] {
        kv.alertHistory.filter { $0.type.contains("fail") }
    }

    var body: some View {
        NavigationStack {
            Group {
                if intruderAlerts.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No Intruder Events")
                            .font(.title2).foregroundColor(.secondary)
                        Text("Intruder photos are captured on your Mac after 2+ failed unlock attempts.\nOpen AppLocker on your Mac to view the photos.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        Spacer()
                    }
                } else {
                    List(intruderAlerts) { alert in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red).font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Failed unlock on \(alert.appName)").font(.subheadline)
                                Text(alert.deviceName).font(.caption).foregroundColor(.secondary)
                                Text(alert.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Intruder Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { kv.decodeAllKeys() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { kv.decodeAllKeys() }
        }
    }
}
#endif
