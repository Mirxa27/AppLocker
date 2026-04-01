// Sources/AppLocker/iOS/ClipboardGuard/iOSClipboardGuardView.swift
#if os(iOS)
import SwiftUI

struct iOSClipboardGuardView: View {
    @StateObject private var vm = iOSClipboardGuard.shared
    @State private var showDelayPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    configCard
                    recentEventsCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Clipboard Guard")
            .toolbar {
                if !vm.recentEvents.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear History") {
                            vm.clearHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Protection Status")
                    .font(.headline)
                Spacer()
                AppStatusBadge(
                    text: vm.isEnabled ? "Active" : "Inactive",
                    color: vm.isEnabled ? AppDesign.success : .secondary
                )
            }

            Toggle("Enable Clipboard Guard", isOn: $vm.isEnabled)
                .tint(AppDesign.accent)

            if vm.isEnabled && vm.secondsUntilClear > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(AppDesign.warning)
                    Text("Auto-clear in \(vm.secondsUntilClear)s")
                        .font(.subheadline)
                        .foregroundStyle(AppDesign.warning)
                    Spacer()
                    Button("Clear Now") {
                        vm.clearNow()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
        }
        .appSurface()
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            HStack {
                Label("Auto-Clear Delay", systemImage: "timer")
                Spacer()
                Picker("Delay", selection: $vm.clearDelaySeconds) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.menu)
            }

            Toggle(isOn: $vm.protectSensitiveData) {
                Label("Enhanced Sensitive Detection", systemImage: "shield.checkered")
            }
        }
        .appSurface()
    }

    @ViewBuilder
    private var recentEventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(vm.recentEvents.count)", color: AppDesign.accent)
            }

            if vm.recentEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Activity")
                        .font(.title3.weight(.semibold))
                    Text("Clipboard changes will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.recentEvents.prefix(10)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.estimatedCharCount > 0 ? "doc.on.clipboard" : "trash")
                            .foregroundStyle(event.estimatedCharCount > 0 ? AppDesign.accent : AppDesign.warning)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            if event.estimatedCharCount > 0 {
                                Text("\(event.estimatedCharCount) characters copied")
                                    .font(.subheadline)
                            } else {
                                Text("Clipboard cleared")
                                    .font(.subheadline)
                                    .foregroundStyle(AppDesign.warning)
                            }
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .appSurface()
    }
}
#endif
