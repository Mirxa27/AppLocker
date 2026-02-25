// Sources/AppLocker/ClipboardGuard/ClipboardGuardView.swift
#if os(macOS)
import SwiftUI

struct ClipboardGuardView: View {
    @ObservedObject var guard_ = ClipboardGuard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clipboard Guard").font(.headline)

            HStack {
                Image(systemName: guard_.isEnabled ? "clipboard.fill" : "clipboard")
                    .font(.title2).foregroundColor(guard_.isEnabled ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guard_.isEnabled ? "Active" : "Inactive").fontWeight(.semibold)
                    if guard_.isEnabled && guard_.secondsUntilClear > 0 {
                        Text("Clears in \(guard_.secondsUntilClear)s").font(.caption).foregroundColor(.orange)
                    } else if guard_.isEnabled {
                        Text("Monitoring clipboard").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $guard_.isEnabled).toggleStyle(.switch).labelsHidden()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 10) {
                Text("Auto-Clear Delay").font(.subheadline).foregroundColor(.secondary)
                Picker("Delay", selection: $guard_.clearDelaySeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .pickerStyle(.segmented)
                Button("Clear Clipboard Now") { guard_.clearNow() }.buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Activity").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear History") { guard_.recentEvents.removeAll() }
                        .buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                }
                if guard_.recentEvents.isEmpty {
                    Text("No clipboard activity recorded").foregroundColor(.secondary).font(.caption)
                } else {
                    List(guard_.recentEvents) { event in
                        HStack {
                            Image(systemName: event.estimatedCharCount == 0 ? "trash" : "doc.on.clipboard")
                                .foregroundColor(event.estimatedCharCount == 0 ? .red : .blue).font(.caption)
                            Text(event.estimatedCharCount == 0 ? "Cleared" : "~\(event.estimatedCharCount) chars")
                                .font(.caption)
                            Spacer()
                            Text(event.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
    }
}
#endif
