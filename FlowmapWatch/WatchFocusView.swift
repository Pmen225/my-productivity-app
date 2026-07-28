import SwiftUI

/// The watch's most-used screen: what is running right now.
///
/// A plain ring stands in for the phone's wheel — there is no room for a
/// queue on this screen, only the active block. Every control below is a
/// `WatchCommand` sent straight to the phone; the watch keeps no timer of its
/// own beyond the redraw tick already running in `WatchStore`.
struct WatchFocusView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    private var snapshot: WatchSnapshot? { store.snapshot }

    var body: some View {
        Group {
            if let snapshot, snapshot.hasActiveSession {
                activeContent(snapshot)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, FlowSpacing.s)
    }

    private func activeContent(_ snapshot: WatchSnapshot) -> some View {
        let remaining = snapshot.remainingSeconds(at: store.now)
        let progress = snapshot.progress(at: store.now)

        return VStack(spacing: FlowSpacing.s) {
            ZStack {
                Circle()
                    .stroke(FlowTheme.separator(scheme), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(FlowTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: FlowSpacing.xxs) {
                    Text(DurationFormatter.countdown(seconds: remaining))
                        .font(FlowFont.countdownCompact)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .accessibilityLabel(DurationFormatter.spokenCountdown(seconds: remaining))

                    Text(snapshot.activeTitle ?? "")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(FlowSpacing.m)
            }
            .padding(.horizontal, FlowSpacing.m)

            controls(paused: snapshot.isPaused)
        }
        .padding(.vertical, FlowSpacing.xs)
    }

    private func controls(paused: Bool) -> some View {
        HStack(spacing: FlowSpacing.m) {
            sideButton(systemImage: "forward.end.fill", label: "Skip this task") {
                store.send(.skip)
            }

            Button {
                store.send(.togglePause)
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(FlowTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paused ? "Resume" : "Pause")

            sideButton(systemImage: "checkmark", label: "Complete task") {
                store.send(.complete)
            }
        }
    }

    private func sideButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(FlowTheme.surface(scheme)))
                .overlay(Circle().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: FlowSpacing.m) {
            Spacer()

            Text("Nothing running")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))

            Button {
                store.send(.startNext)
            } label: {
                Text("Start next")
                    .font(FlowFont.secondary.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, FlowSpacing.l)
                    .padding(.vertical, FlowSpacing.s)
                    .background(Capsule().fill(FlowTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start the next scheduled task")

            Spacer()
        }
    }
}
