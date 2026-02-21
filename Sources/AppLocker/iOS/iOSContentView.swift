#if os(iOS)
import SwiftUI

struct iOSContentView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    @State private var showingUnlockSheet = false
    @State private var targetBundleID = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Remote Control")) {
                    Button(action: {
                        NotificationManager.shared.sendRemoteCommand(.lockAll)
                    }) {
                        Label("Lock All Macs", systemImage: "lock.fill")
                            .foregroundColor(.red)
                    }

                    Button(action: {
                        NotificationManager.shared.sendRemoteCommand(.unlockAll)
                    }) {
                        Label("Unlock All Macs", systemImage: "lock.open.fill")
                            .foregroundColor(.green)
                    }

                    Button(action: {
                        targetBundleID = ""
                        showingUnlockSheet = true
                    }) {
                        Label("Unlock Specific App...", systemImage: "app.badge.checkmark")
                    }
                }

                Section(header: Text("Recent Alerts")) {
                    if notificationManager.notificationHistory.isEmpty {
                        Text("No recent alerts")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(notificationManager.notificationHistory) { record in
                            HStack {
                                Image(systemName: record.type.icon)
                                    .foregroundColor(Color(record.type.color))
                                VStack(alignment: .leading) {
                                    Text(record.appName)
                                        .font(.headline)
                                    Text(record.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("AppLocker Remote")
            .sheet(isPresented: ) {
                VStack(spacing: 20) {
                    Text("Unlock App")
                        .font(.headline)
                    TextField("Bundle ID (e.g. com.apple.Safari)", text: )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                        .autocapitalization(.none)

                    Button("Unlock") {
                        if !targetBundleID.isEmpty {
                            NotificationManager.shared.sendRemoteCommand(.unlockApp, bundleID: targetBundleID)
                            showingUnlockSheet = false
                        }
                    }
                    .disabled(targetBundleID.isEmpty)
                }
                .padding()
                .presentationDetents([.medium])
            }
        }
    }
}

extension Color {
    init(_ string: String) {
        switch string {
        case "red": self = .red
        case "green": self = .green
        case "orange": self = .orange
        default: self = .primary
        }
    }
}
#endif
