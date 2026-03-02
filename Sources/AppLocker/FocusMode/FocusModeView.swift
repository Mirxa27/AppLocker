// Sources/AppLocker/FocusMode/FocusModeView.swift
#if os(macOS)
import SwiftUI

struct FocusModeView: View {
    @ObservedObject var focusManager = FocusModeManager.shared
    @State private var showingProfilePicker = false
    @State private var customDuration = 25
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if focusManager.isActive {
                activeSessionView
            } else {
                setupView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var header: some View {
        HStack {
            Text("Focus Mode")
                .font(.headline)
            Spacer()
            if focusManager.isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose a Focus Profile")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(FocusModeManager.FocusProfile.allCases) { profile in
                            ProfileCard(profile: profile, isSelected: focusManager.selectedProfile == profile) {
                                focusManager.selectedProfile = profile
                                focusManager.sessionDuration = profile.defaultDuration
                            }
                        }
                    }
                }
                
                Divider()
                
                // Duration Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session Duration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Slider(value: $focusManager.sessionDuration, in: 300...7200, step: 300)
                        Text("\(Int(focusManager.sessionDuration / 60)) min")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50)
                    }
                    
                    // Quick presets
                    HStack(spacing: 8) {
                        DurationPresetButton(minutes: 15, duration: $focusManager.sessionDuration)
                        DurationPresetButton(minutes: 25, duration: $focusManager.sessionDuration)
                        DurationPresetButton(minutes: 45, duration: $focusManager.sessionDuration)
                        DurationPresetButton(minutes: 60, duration: $focusManager.sessionDuration)
                        DurationPresetButton(minutes: 90, duration: $focusManager.sessionDuration)
                    }
                }
                
                Divider()
                
                // Break Settings
                Toggle("Allow Breaks", isOn: $focusManager.allowBreaks)
                if focusManager.allowBreaks {
                    HStack {
                        Text("Break Length: \(Int(focusManager.breakDuration / 60)) min")
                        Slider(value: $focusManager.breakDuration, in: 60...900, step: 60)
                    }
                }
                
                // Stats
                if !focusManager.sessionHistory.isEmpty {
                    Divider()
                    FocusStatsView(sessions: focusManager.sessionHistory)
                }
                
                Spacer()
                
                Button {
                    focusManager.startFocus()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Focus Session")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }
    
    private var activeSessionView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Timer Display
            ZStack {
                // Progress Ring
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(
                        focusManager.isOnBreak ? Color.orange : Color.green,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progressValue)
                
                VStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    
                    if focusManager.isOnBreak {
                        Text("BREAK TIME")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.bold)
                    } else {
                        Text(focusManager.selectedProfile.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Status
            if !focusManager.isOnBreak {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: focusManager.selectedProfile.icon)
                            .foregroundColor(profileColor)
                        Text("Profile: \(focusManager.selectedProfile.rawValue)")
                    }
                    .font(.subheadline)
                    
                    Text(focusManager.selectedProfile.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 16) {
                if focusManager.allowBreaks && !focusManager.isOnBreak {
                    Button {
                        focusManager.startBreak()
                    } label: {
                        Label("Take Break", systemImage: "cup.and.saucer.fill")
                    }
                    .buttonStyle(.bordered)
                } else if focusManager.isOnBreak {
                    Button {
                        focusManager.endBreak()
                    } label: {
                        Label("End Break", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button {
                    focusManager.extendSession(minutes: 5)
                } label: {
                    Label("+5 min", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(focusManager.isOnBreak)
                
                Button(role: .destructive) {
                    focusManager.stopFocus(completed: false)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var progressValue: Double {
        let total = focusManager.isOnBreak ? focusManager.breakDuration : focusManager.sessionDuration
        guard total > 0 else { return 1 }
        let remaining = focusManager.timeRemaining
        return 1 - (remaining / total)
    }
    
    private var formattedTime: String {
        let minutes = Int(focusManager.timeRemaining) / 60
        let seconds = Int(focusManager.timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var profileColor: Color {
        switch focusManager.selectedProfile {
        case .work: return .blue
        case .study: return .purple
        case .meeting: return .green
        case .custom: return .orange
        }
    }
}

struct ProfileCard: View {
    let profile: FocusModeManager.FocusProfile
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: profile.icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                
                Text(profile.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(profile.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 30)
                
                Text("\(Int(profile.defaultDuration / 60)) min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding()
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var color: Color {
        switch profile {
        case .work: return .blue
        case .study: return .purple
        case .meeting: return .green
        case .custom: return .orange
        }
    }
}

struct DurationPresetButton: View {
    let minutes: Int
    @Binding var duration: TimeInterval
    
    var isSelected: Bool {
        abs(duration - TimeInterval(minutes * 60)) < 1
    }
    
    var body: some View {
        Button {
            duration = TimeInterval(minutes * 60)
        } label: {
            Text("\(minutes)m")
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct FocusStatsView: View {
    let sessions: [FocusSession]
    
    var todaySessions: [FocusSession] {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDateInToday($0.startTime) }
    }
    
    var totalMinutesToday: Int {
        Int(todaySessions.reduce(0) { $0 + $1.actualDuration } / 60)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Progress")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                StatItem(value: "\(todaySessions.count)", label: "Sessions", icon: "number.circle.fill", color: .blue)
                StatItem(value: "\(totalMinutesToday)", label: "Minutes", icon: "clock.fill", color: .green)
                StatItem(value: "\(todaySessions.filter { $0.completed }.count)", label: "Completed", icon: "checkmark.circle.fill", color: .purple)
            }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
