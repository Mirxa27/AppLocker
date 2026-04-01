// Sources/AppLocker/iOS/FocusMode/iOSFocusModeView.swift
#if os(iOS)
import SwiftUI

struct iOSFocusModeView: View {
    @StateObject private var vm = iOSFocusModeManager.shared
    @State private var showCustomDuration = false
    @State private var customMinutes: Double = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if vm.isActive {
                        activeSessionCard
                    } else {
                        profileSelectionCard
                    }
                    statsCard
                    historyCard
                }
                .padding(16)
            }
            .appScreenBackground()
            .navigationTitle("Focus Mode")
            .toolbar {
                if vm.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End") {
                            vm.stopFocus()
                        }
                        .tint(AppDesign.danger)
                    }
                }
            }
        }
    }

    private var activeSessionCard: some View {
        VStack(spacing: 20) {
            // Timer display
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: vm.progress)
                    .stroke(vm.selectedProfile.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: vm.progress)

                VStack(spacing: 4) {
                    Text(vm.formattedTimeRemaining)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    if vm.isOnBreak {
                        Text("Break")
                            .font(.caption)
                            .foregroundStyle(AppDesign.success)
                    } else {
                        Text(vm.selectedProfile.rawValue)
                            .font(.caption)
                            .foregroundStyle(vm.selectedProfile.color)
                    }
                }
            }
            .padding(.vertical, 12)

            // Profile info
            HStack(spacing: 12) {
                Image(systemName: vm.selectedProfile.icon)
                    .font(.title2)
                    .foregroundStyle(vm.selectedProfile.color)
                    .frame(width: 44, height: 44)
                    .background(vm.selectedProfile.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.selectedProfile.rawValue)
                        .font(.headline)
                    Text(vm.isOnBreak ? "On break" : "Stay focused!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                AppStatusBadge(
                    text: vm.isOnBreak ? "Break" : "Active",
                    color: vm.isOnBreak ? AppDesign.success : AppDesign.accent
                )
            }

            // Controls
            HStack(spacing: 12) {
                if vm.isOnBreak {
                    Button {
                        vm.skipBreak()
                    } label: {
                        Label("Skip Break", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppDesign.accent)
                } else if vm.allowBreaks {
                    Button {
                        vm.startBreak()
                    } label: {
                        Label("Take Break", systemImage: "cup.and.saucer.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppDesign.success)
                }

                Button {
                    vm.extendSession(minutes: 5)
                } label: {
                    Label("+5 min", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .appSurface()
    }

    private var profileSelectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Profile")
                .font(.headline)

            ForEach(iOSFocusModeManager.FocusProfile.allCases) { profile in
                Button {
                    vm.startFocus(profile: profile)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: profile.icon)
                            .font(.title3)
                            .foregroundStyle(profile.color)
                            .frame(width: 36, height: 36)
                            .background(profile.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(profile.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(formatDuration(profile.defaultDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .appSurface()
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 12
            ) {
                AppMetricCard(
                    title: "Sessions",
                    value: "\(vm.completedSessionsToday)",
                    subtitle: "completed",
                    icon: "checkmark.circle.fill",
                    color: AppDesign.success
                )
                AppMetricCard(
                    title: "Focus Time",
                    value: "\(vm.totalFocusMinutesToday)m",
                    subtitle: "total today",
                    icon: "timer",
                    color: AppDesign.accent
                )
                AppMetricCard(
                    title: "Streak",
                    value: "\(vm.currentStreak)",
                    subtitle: "day streak",
                    icon: "flame.fill",
                    color: AppDesign.warning
                )
                AppMetricCard(
                    title: "This Week",
                    value: "\(vm.completedSessionsThisWeek)",
                    subtitle: "sessions",
                    icon: "calendar",
                    color: AppDesign.accentSecondary
                )
            }
        }
        .appSurface()
    }

    @ViewBuilder
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                Spacer()
                AppStatusBadge(text: "\(vm.sessionHistory.count)", color: AppDesign.accent)
            }

            if vm.sessionHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("No Sessions Yet")
                        .font(.title3.weight(.semibold))
                    Text("Start a focus session to track your productivity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.sessionHistory.prefix(5)) { session in
                    HStack(spacing: 10) {
                        Image(systemName: session.profile.icon)
                            .foregroundStyle(session.profile.color)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.profile.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Text(session.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(session.formattedDuration)
                                .font(.subheadline)
                            AppStatusBadge(
                                text: session.completed ? "Completed" : "Stopped",
                                color: session.completed ? AppDesign.success : .secondary
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .appSurface()
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return "\(minutes) min"
    }
}
#endif
