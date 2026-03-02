// Sources/AppLocker/AppQuotas/AppQuotasView.swift
#if os(macOS)
import SwiftUI

struct AppQuotasView: View {
    @ObservedObject var quotaManager = AppQuotaManager.shared
    @ObservedObject var appMonitor = AppMonitor.shared
    @State private var showingAddQuota = false
    @State private var selectedApp: LockedAppInfo?
    @State private var limitMinutes = 30
    @State private var allowOverride = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("App Usage Quotas")
                    .font(.headline)
                Spacer()
                
                Toggle("Monitor", isOn: $quotaManager.isMonitoring)
                    .toggleStyle(.switch)
                    .onChange(of: quotaManager.isMonitoring) { newValue in
                        newValue ? quotaManager.startMonitoring() : quotaManager.stopMonitoring()
                    }
                
                Button {
                    showingAddQuota = true
                } label: {
                    Label("Add Quota", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // Content
            if quotaManager.quotas.isEmpty {
                emptyState
            } else {
                quotasList
            }
        }
        .sheet(isPresented: $showingAddQuota) {
            AddQuotaSheet(
                lockedApps: appMonitor.lockedApps,
                onSave: { bundleID, minutes, override in
                    quotaManager.setQuota(bundleID: bundleID, minutes: minutes, allowOverride: override)
                }
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Usage Quotas Set")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Set daily time limits for your locked apps to help build healthier habits.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Button {
                showingAddQuota = true
            } label: {
                Text("Add Your First Quota")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var quotasList: some View {
        List {
            Section {
                ForEach(quotaManager.quotas) { quota in
                    QuotaRow(
                        quota: quota,
                        appName: appName(for: quota.bundleID),
                        usagePercentage: quotaManager.usagePercentage(for: quota.bundleID),
                        remainingMinutes: quotaManager.remainingMinutes(for: quota.bundleID),
                        formattedUsage: quotaManager.formattedUsage(for: quota.bundleID)
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            quotaManager.removeQuota(bundleID: quota.bundleID)
                        } label: {
                            Label("Remove Quota", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(quotaManager.quotas.count) Apps")
                    Spacer()
                    Button("Reset Daily") {
                        quotaManager.resetDailyUsage()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            
            Section("How It Works") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Monitors active app usage time", systemImage: "eye.fill")
                    Label("Warns 5 minutes before limit", systemImage: "exclamationmark.triangle.fill")
                    Label("Can terminate apps at limit", systemImage: "xmark.octagon.fill")
                    Label("Resets automatically each day", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .listStyle(.inset)
    }
    
    private func appName(for bundleID: String) -> String {
        appMonitor.lockedApps.first { $0.bundleID == bundleID }?.displayName ?? bundleID
    }
}

struct QuotaRow: View {
    let quota: AppQuota
    let appName: String
    let usagePercentage: Double
    let remainingMinutes: Int
    let formattedUsage: String
    
    var statusColor: Color {
        if quota.limitReached {
            return .red
        } else if usagePercentage >= 80 {
            return .orange
        } else {
            return .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.headline)
                    Text("Limit: \(quota.dailyLimitMinutes) min/day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedUsage)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                    
                    if quota.limitReached {
                        Text("LIMIT REACHED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    } else {
                        Text("\(remainingMinutes) min remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geo.size.width * CGFloat(usagePercentage / 100), height: 8)
                        .cornerRadius(4)
                        .animation(.easeInOut, value: usagePercentage)
                }
            }
            .frame(height: 8)
            
            if quota.allowOverride {
                Label("Override allowed", systemImage: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddQuotaSheet: View {
    let lockedApps: [LockedAppInfo]
    let onSave: (String, Int, Bool) -> Void
    
    @State private var selectedBundleID = ""
    @State private var limitMinutes = 30
    @State private var allowOverride = false
    @Environment(\.dismiss) private var dismiss
    
    var availableApps: [LockedAppInfo] {
        lockedApps // Could filter out apps that already have quotas
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Set App Quota")
                .font(.headline)
            
            if availableApps.isEmpty {
                Text("No locked apps available")
                    .foregroundColor(.secondary)
            } else {
                Picker("App", selection: $selectedBundleID) {
                    Text("Select an app").tag("")
                    ForEach(availableApps) { app in
                        Text(app.displayName).tag(app.bundleID)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
                
                VStack(alignment: .leading) {
                    Text("Daily Limit: \(limitMinutes) minutes")
                    Slider(value: .init(
                        get: { Double(limitMinutes) },
                        set: { limitMinutes = Int($0) }
                    ), in: 5...240, step: 5)
                }
                .frame(width: 250)
                
                Toggle("Allow Override", isOn: $allowOverride)
                    .frame(width: 250)
                
                Text("If enabled, you'll be warned but not blocked when the limit is reached.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 250)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    if !selectedBundleID.isEmpty {
                        onSave(selectedBundleID, limitMinutes, allowOverride)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBundleID.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 320)
        .onAppear {
            if let first = availableApps.first {
                selectedBundleID = first.bundleID
            }
        }
    }
}

#endif
