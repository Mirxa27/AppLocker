// Sources/AppLocker/NetworkMonitor/NetworkMonitorView.swift
#if os(macOS)
import SwiftUI

struct NetworkMonitorView: View {
    @ObservedObject var monitor = NetworkMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Network Monitor").font(.headline)
                Text("(\(monitor.connections.count))").font(.caption).foregroundColor(.secondary)
                Spacer()
                Toggle("Locked apps only", isOn: $monitor.showLockedAppsOnly)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle(monitor.isPaused ? "Paused" : "Live", isOn: $monitor.isPaused)
                    .toggleStyle(.switch).font(.caption)
            }
            .padding()
            Divider()

            if monitor.connections.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "network").font(.system(size: 48)).foregroundColor(.secondary)
                    Text(monitor.showLockedAppsOnly
                         ? "No connections from locked apps"
                         : "No active connections found")
                        .foregroundColor(.secondary)
                    Text("Toggle 'Locked apps only' to see all connections")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(monitor.groupedConnections, id: \.name) { group in
                        Section {
                            ForEach(group.connections) { conn in
                                ConnectionRow(conn: conn)
                            }
                        } header: {
                            HStack {
                                Text(group.name).font(.subheadline).fontWeight(.semibold)
                                Text("(\(group.connections.count))").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("Terminate") {
                                    if let app = NSWorkspace.shared.runningApplications
                                        .first(where: { ($0.localizedName ?? "") == group.name }) {
                                        app.forceTerminate()
                                        AppMonitor.shared.addLog("Network Monitor: terminated \(group.name)")
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.mini).foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ConnectionRow: View {
    let conn: NetworkConnection

    var stateColor: Color {
        switch conn.state {
        case "ESTABLISHED": return .green
        case "LISTEN": return .blue
        case "CLOSE_WAIT", "TIME_WAIT", "FIN_WAIT1", "FIN_WAIT2": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("\(conn.remoteIP):\(conn.remotePort)")
                        .font(.system(.caption, design: .monospaced))
                    if !conn.remoteOrg.isEmpty {
                        Text("· \(conn.remoteOrg)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text("\(conn.proto) \(conn.state.isEmpty ? "" : conn.state) · local: \(conn.localAddress)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
#endif
