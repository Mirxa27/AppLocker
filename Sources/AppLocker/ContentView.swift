// ContentView.swift
// Main application view with enhanced app locking, schedules, usage stats, and settings

import SwiftUI
import LocalAuthentication

// MARK: - AppIcon helper to display real app icons
struct AppIconView: NSViewRepresentable {
    let bundleID: String
    let path: String?
    let size: CGFloat
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = size * 0.2
        imageView.layer?.masksToBounds = true
        
        if let path = path {
            imageView.image = NSWorkspace.shared.icon(forFile: path)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            imageView.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            imageView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
        }
        
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var appMonitor = AppMonitor.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var passcode = ""
    @State private var isSettingUp = false
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var showingSetupSuccess = false
    @State private var selectedTab = 0
    @State private var unlockPasscode = ""
    @State private var appSearchText = ""
    @State private var addAppMode = 0
    
    var body: some View {
        Group {
            if !authManager.isPasscodeSet() {
                setupView
            } else if authManager.isAuthenticated {
                mainView
            } else {
                authenticationView
            }
        }
        .sheet(isPresented: $appMonitor.showUnlockDialog) {
            unlockSheet
        }
    }
    
    // MARK: - Unlock Sheet (when blocked app is detected)
    
    private var unlockSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("App Blocked")
                .font(.title)
                .bold()
            
            if let appName = appMonitor.lastBlockedAppName {
                Text("\"\(appName)\" is locked by AppLocker")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if authManager.isLockedOut {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Too many failed attempts")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Try again in \(authManager.lockoutRemainingFormatted)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                SecureField("Enter passcode to unlock", text: $unlockPasscode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 250)
                    .onSubmit { attemptUnlock() }
            }
            
            HStack(spacing: 15) {
                Button("Dismiss") {
                    unlockPasscode = ""
                    appMonitor.showUnlockDialog = false
                }
                .buttonStyle(.bordered)
                
                Button("Unlock (\(appMonitor.unlockDurationFormatted))") {
                    attemptUnlock()
                }
                .buttonStyle(.borderedProminent)
                .disabled(unlockPasscode.isEmpty || authManager.isLockedOut)
            }
            
            if authManager.canUseBiometrics() && !authManager.isLockedOut {
                Button {
                    authManager.authenticateWithBiometrics { success, _ in
                        if success, let bundleID = appMonitor.lastBlockedBundleID {
                            appMonitor.temporarilyUnlock(bundleID: bundleID)
                            unlockPasscode = ""
                            appMonitor.showUnlockDialog = false
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "touchid")
                        Text("Use Touch ID")
                    }
                }
                .buttonStyle(.borderless)
            }
            
            if authManager.failedAttempts > 0 && !authManager.isLockedOut {
                Text("\(authManager.failedAttempts) failed attempt(s)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    private func attemptUnlock() {
        if authManager.verifyPasscode(unlockPasscode) {
            if let bundleID = appMonitor.lastBlockedBundleID {
                appMonitor.temporarilyUnlock(bundleID: bundleID)
            }
            authManager.resetFailedAttempts()
            unlockPasscode = ""
            appMonitor.showUnlockDialog = false
        } else {
            authManager.recordFailedAttempt()
            if let appName = appMonitor.lastBlockedAppName,
               let bundleID = appMonitor.lastBlockedBundleID {
                notificationManager.sendFailedAuthNotification(appName: appName, bundleID: bundleID)
                appMonitor.recordUsage(bundleID: bundleID, appName: appName, event: .failedAttempt)
            }
            unlockPasscode = ""
        }
    }
    
    // MARK: - Setup View
    
    private var setupView: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("Welcome to AppLocker")
                .font(.largeTitle)
                .bold()
            
            Text("Set up your security passcode to lock apps")
                .foregroundColor(.secondary)
            
            if isSettingUp {
                VStack(spacing: 15) {
                    SecureField("Enter passcode (4+ chars)", text: $newPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 250)
                    
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 250)
                    
                    if !newPasscode.isEmpty && newPasscode != confirmPasscode && !confirmPasscode.isEmpty {
                        Text("Passcodes don't match")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // Password strength indicator
                    if !newPasscode.isEmpty {
                        PasswordStrengthView(password: newPasscode)
                    }
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            isSettingUp = false
                            newPasscode = ""
                            confirmPasscode = ""
                        }
                        
                        Button("Set Passcode") {
                            if newPasscode == confirmPasscode && newPasscode.count >= 4 {
                                if authManager.setPasscode(newPasscode) {
                                    isSettingUp = false
                                    showingSetupSuccess = true
                                    newPasscode = ""
                                    confirmPasscode = ""
                                }
                            }
                        }
                        .disabled(newPasscode != confirmPasscode || newPasscode.count < 4)
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button("Get Started") {
                    isSettingUp = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Success", isPresented: $showingSetupSuccess) {
            Button("OK") { }
        } message: {
            Text("Your passcode has been set! You can now lock apps.")
        }
    }
    
    // MARK: - Authentication View
    
    private var authenticationView: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("AppLocker is Locked")
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 15) {
                if authManager.isLockedOut {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Too many failed attempts")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Try again in \(authManager.lockoutRemainingFormatted)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    SecureField("Enter passcode", text: $passcode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 200)
                        .onSubmit {
                            _ = authManager.authenticate(withPasscode: passcode)
                            if authManager.isAuthenticated { passcode = "" }
                        }
                    
                    if let error = authManager.authenticationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button("Unlock") {
                        _ = authManager.authenticate(withPasscode: passcode)
                        if authManager.isAuthenticated { passcode = "" }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(passcode.isEmpty)
                }
            }
            
            if authManager.canUseBiometrics() && !authManager.isLockedOut {
                Button {
                    authManager.authenticateWithBiometrics { _, _ in }
                } label: {
                    HStack {
                        Image(systemName: "touchid")
                        Text("Use Touch ID")
                    }
                }
                .buttonStyle(.borderless)
                .padding(.top)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Main View (Authenticated)
    
    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AppLocker")
                        .font(.title2)
                        .bold()
                    Text("\(appMonitor.lockedApps.count) apps locked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Monitoring toggle
                HStack(spacing: 8) {
                    Circle()
                        .fill(appMonitor.isMonitoring ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(appMonitor.isMonitoring ? "Active" : "Off")
                        .font(.caption)
                    Toggle("", isOn: Binding(
                        get: { appMonitor.isMonitoring },
                        set: { $0 ? appMonitor.startMonitoring() : appMonitor.stopMonitoring() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                
                Button("Lock") {
                    authManager.logout()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Accessibility warning banner
            if !appMonitor.hasAccessibilityPermissions() {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text("Accessibility permission required for blocking to work!")
                        .font(.caption)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Grant Access") {
                        appMonitor.requestAccessibilityPermissions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.red)
            }
            
            // Tab bar
            Picker("", selection: $selectedTab) {
                Text("Locked Apps").tag(0)
                Text("Add Apps").tag(1)
                Text("Activity").tag(2)
                Text("Stats").tag(3)
                Text("Notifications").tag(4)
                Text("Settings").tag(5)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Tab content
            switch selectedTab {
            case 0: lockedAppsTab
            case 1: addAppsTab
            case 2: activityLogTab
            case 3: usageStatsTab
            case 4: notificationsTab
            case 5: settingsTab
            default: lockedAppsTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appMonitor.requestAccessibilityPermissions()
        }
    }
    
    // MARK: - Locked Apps Tab
    
    private var lockedAppsTab: some View {
        VStack(spacing: 0) {
            if appMonitor.lockedApps.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No apps locked yet")
                        .font(.headline)
                    Text("Go to 'Add Apps' tab to lock your first app")
                        .foregroundColor(.secondary)
                    Button("Add Apps") {
                        selectedTab = 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appMonitor.lockedApps) { app in
                        LockedAppRow(app: app)
                    }
                }
            }
        }
    }
    
    // MARK: - Add Apps Tab
    
    private var addAppsTab: some View {
        VStack(spacing: 15) {
            // Action buttons
            HStack(spacing: 10) {
                Button {
                    appMonitor.addAppFromFilePicker()
                } label: {
                    Label("Browse .app File", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                
                Button {
                    appMonitor.refreshInstalledApps()
                    appMonitor.refreshRunningApps()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            
            // Filter
            Picker("", selection: $addAppMode) {
                Text("All Installed (\(appMonitor.installedApps.count))").tag(0)
                Text("Currently Running (\(appMonitor.runningApps.count))").tag(1)
            }
            .pickerStyle(.segmented)
            
            // Search
            TextField("Search apps...", text: $appSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            let displayApps = filteredApps
            
            if displayApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No apps found")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(displayApps) { app in
                    let isLocked = appMonitor.isAppLocked(bundleID: app.bundleID)
                    
                    HStack(spacing: 12) {
                        AppIconView(bundleID: app.bundleID, path: app.path, size: 28)
                            .frame(width: 28, height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.bundleID)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if isLocked {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                Text("Locked")
                                    .font(.caption)
                            }
                            .foregroundColor(.red)
                            
                            Button("Remove") {
                                appMonitor.removeLockedApp(bundleID: app.bundleID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button {
                                appMonitor.addLockedApp(info: app)
                            } label: {
                                Label("Lock", systemImage: "lock.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .onAppear {
            appMonitor.refreshInstalledApps()
            appMonitor.refreshRunningApps()
        }
    }
    
    private var filteredApps: [LockedAppInfo] {
        let source = addAppMode == 0 ? appMonitor.installedApps : appMonitor.runningApps
        if appSearchText.isEmpty {
            return source
        }
        return source.filter {
            $0.displayName.localizedCaseInsensitiveContains(appSearchText) ||
            $0.bundleID.localizedCaseInsensitiveContains(appSearchText)
        }
    }
    
    // MARK: - Activity Log Tab
    
    private var activityLogTab: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                
                Text("\(appMonitor.blockLog.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !appMonitor.blockLog.isEmpty {
                    Button("Clear") {
                        appMonitor.clearLog()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            
            if appMonitor.blockLog.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No activity yet")
                        .foregroundColor(.secondary)
                    Text("Start monitoring and blocking events will appear here in real-time.\nLogs are persisted across app restarts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(Array(appMonitor.blockLog.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(logEntryColor(entry))
                }
            }
        }
        .padding(.top)
    }
    
    private func logEntryColor(_ entry: String) -> Color {
        if entry.contains("BLOCKING") { return .red }
        if entry.contains("unlocked") { return .green }
        if entry.contains("Auto-locked") { return .orange }
        if entry.contains("started") { return .blue }
        if entry.contains("stopped") { return .gray }
        return .primary
    }
    
    // MARK: - Usage Stats Tab
    
    @State private var statsPeriod = 0 // 0=all, 1=today, 2=week, 3=month
    
    private var usageStatsTab: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Usage Statistics")
                    .font(.headline)
                Spacer()
                
                Picker("Period", selection: $statsPeriod) {
                    Text("All Time").tag(0)
                    Text("Today").tag(1)
                    Text("This Week").tag(2)
                    Text("This Month").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 350)
            }
            .padding(.horizontal)
            
            let stats = statsForPeriod
            
            if stats.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No usage data yet")
                        .foregroundColor(.secondary)
                    Text("Statistics will appear after apps are blocked or unlocked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Summary cards
                HStack(spacing: 15) {
                    StatCard(title: "Total Blocks", value: "\(stats.reduce(0) { $0 + $1.blockedCount })", icon: "hand.raised.fill", color: .orange)
                    StatCard(title: "Unlocks", value: "\(stats.reduce(0) { $0 + $1.unlockedCount })", icon: "lock.open.fill", color: .green)
                    StatCard(title: "Failed Attempts", value: "\(stats.reduce(0) { $0 + $1.failedAttemptCount })", icon: "exclamationmark.triangle.fill", color: .red)
                }
                .padding(.horizontal)
                
                // Per-app breakdown
                List(stats) { stat in
                    HStack(spacing: 12) {
                        AppIconView(bundleID: stat.bundleID, path: nil, size: 28)
                            .frame(width: 28, height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.appName)
                                .font(.system(size: 13, weight: .medium))
                            if let lastBlocked = stat.lastBlocked {
                                Text("Last blocked: \(formatDate(lastBlocked))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            StatBadge(count: stat.blockedCount, label: "blocked", color: .orange)
                            StatBadge(count: stat.unlockedCount, label: "unlocked", color: .green)
                            StatBadge(count: stat.failedAttemptCount, label: "failed", color: .red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.top)
    }
    
    private var statsForPeriod: [UsageStats] {
        switch statsPeriod {
        case 1: return appMonitor.getUsageStatsForPeriod(days: 1)
        case 2: return appMonitor.getUsageStatsForPeriod(days: 7)
        case 3: return appMonitor.getUsageStatsForPeriod(days: 30)
        default: return appMonitor.getUsageStats()
        }
    }
    
    // MARK: - Notifications Tab
    
    private var notificationsTab: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Notification History")
                    .font(.headline)
                
                Spacer()
                
                Text("\(notificationManager.notificationHistory.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !notificationManager.notificationHistory.isEmpty {
                    Button("Clear") {
                        notificationManager.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            
            if notificationManager.notificationHistory.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No notifications yet")
                        .foregroundColor(.secondary)
                    Text("Activity will appear here when locked apps are accessed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(notificationManager.notificationHistory) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.type.icon)
                            .font(.title3)
                            .foregroundColor(colorForType(record.type))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.type.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colorForType(record.type))
                                Text("- \(record.appName)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text(record.bundleID)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDate(record.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.top)
    }
    
    private func colorForType(_ type: NotificationRecord.NotificationType) -> Color {
        switch type {
        case .blocked: return .orange
        case .unlocked: return .green
        case .failedAttempt: return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    // MARK: - Settings Tab
    
    @State private var showChangePasscode = false
    @State private var currentPasscode = ""
    @State private var newSettingsPasscode = ""
    @State private var confirmSettingsPasscode = ""
    @State private var passcodeChangeError: String?
    @State private var passcodeChangeSuccess = false
    @State private var showResetConfirmation = false
    @State private var newCategoryName = ""
    @State private var showAddCategory = false
    
    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Security section
                GroupBox("Security") {
                    VStack(alignment: .leading, spacing: 15) {
                        // Change Passcode
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Change Passcode")
                                    .font(.headline)
                                Text("Update your security passcode")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showChangePasscode = true
                                currentPasscode = ""
                                newSettingsPasscode = ""
                                confirmSettingsPasscode = ""
                                passcodeChangeError = nil
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if showChangePasscode {
                            VStack(spacing: 10) {
                                SecureField("Current passcode", text: $currentPasscode)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 250)
                                
                                SecureField("New passcode (4+ chars)", text: $newSettingsPasscode)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 250)
                                
                                SecureField("Confirm new passcode", text: $confirmSettingsPasscode)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 250)
                                
                                if let error = passcodeChangeError {
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                
                                if !newSettingsPasscode.isEmpty {
                                    PasswordStrengthView(password: newSettingsPasscode)
                                }
                                
                                HStack(spacing: 10) {
                                    Button("Cancel") {
                                        showChangePasscode = false
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("Update Passcode") {
                                        guard newSettingsPasscode == confirmSettingsPasscode else {
                                            passcodeChangeError = "New passcodes don't match"
                                            return
                                        }
                                        let result = authManager.changePasscode(
                                            currentPasscode: currentPasscode,
                                            newPasscode: newSettingsPasscode
                                        )
                                        if result.success {
                                            showChangePasscode = false
                                            passcodeChangeSuccess = true
                                        } else {
                                            passcodeChangeError = result.error
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(currentPasscode.isEmpty || newSettingsPasscode.count < 4 || newSettingsPasscode != confirmSettingsPasscode)
                                }
                            }
                            .padding(.top, 5)
                        }
                        
                        Divider()
                        
                        // Auto-lock on sleep
                        Toggle(isOn: $appMonitor.autoLockOnSleep) {
                            VStack(alignment: .leading) {
                                Text("Auto-Lock on Sleep")
                                    .font(.headline)
                                Text("Automatically lock all temporarily unlocked apps and AppLocker when the screen sleeps or lid closes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: appMonitor.autoLockOnSleep) { newValue in
                            _ = newValue
                            appMonitor.saveSettings()
                        }
                        
                        Divider()
                        
                        // Failed attempts info
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Lockout Protection")
                                    .font(.headline)
                                Text("After 5 failed attempts, a time-based lockout escalates automatically")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if authManager.failedAttempts > 0 {
                                VStack(alignment: .trailing) {
                                    Text("\(authManager.failedAttempts) failed attempts")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Button("Reset") {
                                        authManager.resetFailedAttempts()
                                    }
                                    .controlSize(.small)
                                }
                            } else {
                                Text("No failed attempts")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Unlock Duration section
                GroupBox("Unlock Duration") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temporary Unlock Duration")
                            .font(.headline)
                        Text("How long an app stays unlocked after successful authentication")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Duration", selection: $appMonitor.unlockDuration) {
                            Text("30 seconds").tag(TimeInterval(30))
                            Text("1 minute").tag(TimeInterval(60))
                            Text("2 minutes").tag(TimeInterval(120))
                            Text("5 minutes").tag(TimeInterval(300))
                            Text("10 minutes").tag(TimeInterval(600))
                            Text("15 minutes").tag(TimeInterval(900))
                            Text("30 minutes").tag(TimeInterval(1800))
                            Text("1 hour").tag(TimeInterval(3600))
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: appMonitor.unlockDuration) { newValue in
                            _ = newValue
                            appMonitor.saveSettings()
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Notifications section
                GroupBox("Notifications") {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle(isOn: $notificationManager.notificationsEnabled) {
                            VStack(alignment: .leading) {
                                Text("Enable Notifications")
                                    .font(.headline)
                                Text("Get notified when locked apps are accessed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: notificationManager.notificationsEnabled) { newValue in
                            _ = newValue
                            notificationManager.saveSettings()
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $notificationManager.crossDeviceEnabled) {
                            VStack(alignment: .leading) {
                                Text("Cross-Device Alerts")
                                    .font(.headline)
                                Text("Sync alerts via iCloud to your other Apple devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: notificationManager.crossDeviceEnabled) { newValue in
                            _ = newValue
                            notificationManager.saveSettings()
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Failed Attempt Alerts")
                                .font(.headline)
                            Text("Critical notifications are sent for failed unlock attempts and synced to all devices immediately")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "iphone")
                                Image(systemName: "ipad")
                                Image(systemName: "laptopcomputer")
                                Image(systemName: "applewatch")
                                Text("All linked Apple devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 3)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Export/Import section
                GroupBox("Backup & Restore") {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Export Configuration")
                                    .font(.headline)
                                Text("Save your locked apps, categories, and settings to a file")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                appMonitor.exportToFile()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Import Configuration")
                                    .font(.headline)
                                Text("Load a previously exported configuration file")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                appMonitor.importFromFile()
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Permissions section
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if appMonitor.hasAccessibilityPermissions() {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Accessibility: Granted")
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Accessibility: Required")
                                
                                Spacer()
                                
                                Button("Grant") {
                                    appMonitor.requestAccessibilityPermissions()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.blue)
                            Text("Notifications: Check System Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                
                // Danger zone
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Reset All Data")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("Delete passcode, locked apps, and all settings. This cannot be undone.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Reset Everything") {
                                showResetConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 5)
                } label: {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
                
                // About section
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AppLocker v3.0")
                            .font(.headline)
                        Text("Protect your macOS apps with passcode and Touch ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Features: App locking, schedules, usage tracking, categories, export/import, auto-lock, lockout protection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding()
        }
        .alert("Passcode Changed", isPresented: $passcodeChangeSuccess) {
            Button("OK") { }
        } message: {
            Text("Your passcode has been updated successfully.")
        }
        .alert("Reset All Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Everything", role: .destructive) {
                appMonitor.stopMonitoring()
                appMonitor.lockedApps.removeAll()
                appMonitor.clearLog()
                _ = authManager.resetAllData()
            }
        } message: {
            Text("This will delete your passcode, all locked apps, activity logs, and settings. You will need to set up AppLocker again. This cannot be undone.")
        }
    }
}

// MARK: - Locked App Row with Schedule Support

struct LockedAppRow: View {
    let app: LockedAppInfo
    @ObservedObject private var appMonitor = AppMonitor.shared
    @State private var showSchedule = false
    @State private var editSchedule: LockSchedule
    
    init(app: LockedAppInfo) {
        self.app = app
        self._editSchedule = State(initialValue: app.schedule ?? LockSchedule())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(bundleID: app.bundleID, path: app.path, size: 32)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let category = app.category {
                            Text("| \(category)")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                }
                
                Spacer()
                
                if let schedule = app.schedule, schedule.enabled {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Scheduled")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(schedule.startTimeFormatted)-\(schedule.endTimeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Always Locked")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
                
                Button {
                    showSchedule.toggle()
                } label: {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Set schedule")
                
                Button {
                    appMonitor.removeLockedApp(bundleID: app.bundleID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            
            if showSchedule {
                ScheduleEditorView(
                    schedule: $editSchedule,
                    onSave: {
                        appMonitor.updateAppSchedule(bundleID: app.bundleID, schedule: editSchedule.enabled ? editSchedule : nil)
                        showSchedule = false
                    },
                    onCancel: {
                        editSchedule = app.schedule ?? LockSchedule()
                        showSchedule = false
                    }
                )
                .padding(.top, 8)
                .padding(.leading, 44)
            }
        }
    }
}

// MARK: - Schedule Editor

struct ScheduleEditorView: View {
    @Binding var schedule: LockSchedule
    let onSave: () -> Void
    let onCancel: () -> Void
    
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable Schedule", isOn: $schedule.enabled)
                .font(.subheadline)
            
            if schedule.enabled {
                HStack(spacing: 15) {
                    VStack(alignment: .leading) {
                        Text("Start")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Picker("Hour", selection: $schedule.startHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .frame(width: 60)
                            Text(":")
                            Picker("Min", selection: $schedule.startMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .frame(width: 60)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("End")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Picker("Hour", selection: $schedule.endHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .frame(width: 60)
                            Text(":")
                            Picker("Min", selection: $schedule.endMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .frame(width: 60)
                        }
                    }
                }
                
                // Day selector
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in
                        let isActive = schedule.activeDays.contains(day)
                        Button(dayNames[day - 1]) {
                            if isActive {
                                schedule.activeDays.remove(day)
                            } else {
                                schedule.activeDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(isActive ? .blue : .gray)
                        .controlSize(.small)
                    }
                }
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Save Schedule", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Password Strength Indicator

struct PasswordStrengthView: View {
    let password: String
    
    private var strength: (level: Int, label: String, color: Color) {
        var score = 0
        if password.count >= 4 { score += 1 }
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 1 }
        
        switch score {
        case 0...2: return (score, "Weak", .red)
        case 3...4: return (score, "Medium", .orange)
        default: return (score, "Strong", .green)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < strength.level ? strength.color : Color.gray.opacity(0.3))
                    .frame(width: 30, height: 4)
            }
            Text(strength.label)
                .font(.caption2)
                .foregroundColor(strength.color)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title)
                .bold()
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        if count > 0 {
            VStack(spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(color)
            .frame(minWidth: 40)
        }
    }
}
