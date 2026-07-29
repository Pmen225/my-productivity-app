import SwiftUI

/// The mock's merged Map + Today page: the mind map and the day's plan as two
/// panes of one destination, switched by a `Map | Today` toggle in the nav
/// bar's centre.
///
/// Decision 3 merges the two; decision 4 settles how. There is **no swipe**
/// between panes — the map canvas already owns one-finger drag, and a
/// horizontal page swipe over the same surface would either be eaten by the
/// canvas's pan or break panning to win. The toggle is the only way across.
///
/// Only the active pane is in the hierarchy. The mock slides a 750px track
/// with both panes on it; doing that here would put two screens' toolbars in
/// the same nav bar at once, and the user-visible result — panes slide — is
/// the same either way.
struct MapTodayScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Pane { case map, today }

    @State private var pane: Pane = .map
    @State private var scope: TodayScope = .day

    var body: some View {
        ZStack {
            if pane == .map {
                MapListView(showsScreenTitle: false)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                todayPane
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                MapTodayToggle(pane: $pane, scope: $scope)
            }
        }
    }

    @ViewBuilder
    private var todayPane: some View {
        if scope == .day {
            TodayView()
        } else {
            ScopeAgendaView(scope: scope)
        }
    }
}

/// The mock's two-segment control: `Map` on the left, the current scope on the
/// right. Tapping the right segment opens the day's plan; holding it and
/// dragging up or down previews Today / Week / Month and commits on release
/// (decision 5).
private struct MapTodayToggle: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var pane: MapTodayScreen.Pane
    @Binding var scope: TodayScope

    /// Non-nil while the hold-and-drag is live: the scope the finger is
    /// currently over, shown in place of the committed one.
    @State private var previewScope: TodayScope?

    /// How far the finger travels before the preview steps to the next scope.
    private static let stepHeight: CGFloat = 34

    private var shownScope: TodayScope { previewScope ?? scope }

    var body: some View {
        HStack(spacing: FlowSpacing.xxs) {
            segment(title: "Map", isSelected: pane == .map) {
                select(.map)
            }
            scopeSegment
        }
        .padding(FlowSpacing.xxs)
        .background(Capsule().fill(FlowTheme.surfaceSunken(scheme)))
    }

    private var scopeSegment: some View {
        VStack(spacing: 3) {
            Text(shownScope.paneTitle)
                .font(FlowFont.chromeLabel)
                .lineLimit(1)
                .fixedSize()
            scopeDots
        }
        .foregroundStyle(pane == .today ? .white : FlowTheme.secondaryText(scheme))
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 34)
        .background(Capsule().fill(pane == .today ? FlowTheme.accentFill : .clear))
        .contentShape(Capsule())
        .gesture(scopeGesture)
        .accessibilityElement()
        .accessibilityLabel("\(shownScope.paneTitle) plan")
        .accessibilityHint("Double tap to open. Hold and drag up or down for Today, Week or Month.")
        .accessibilityAddTraits(pane == .today ? [.isButton, .isSelected] : .isButton)
    }

    /// Three dots under the label, the current scope's one filled — the mock's
    /// hint that this segment holds more than one thing.
    private var scopeDots: some View {
        HStack(spacing: 3) {
            ForEach(TodayScope.allCases) { option in
                Circle()
                    .fill(option == shownScope ? Color.white : FlowTheme.tertiaryText(scheme))
                    .opacity(option == shownScope ? 1 : 0.5)
                    .frame(width: 3, height: 3)
            }
        }
    }

    private var scopeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                // `.second` means the hold succeeded; the drag that follows
                // picks the scope, so a plain tap never reaches this.
                guard case .second(true, let drag) = value else { return }
                previewScope = scopeFromDrag(drag?.translation.height ?? 0)
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                let committed = scopeFromDrag(drag?.translation.height ?? 0)
                previewScope = nil
                animated {
                    scope = committed
                    pane = .today
                }
            }
            .simultaneously(with: TapGesture().onEnded { select(.today) })
    }

    /// Drag up for the shorter horizon, down for the longer one, starting from
    /// whatever is committed.
    private func scopeFromDrag(_ height: CGFloat) -> TodayScope {
        let all = TodayScope.allCases
        guard let current = all.firstIndex(of: scope) else { return scope }
        let steps = Int((height / Self.stepHeight).rounded())
        let index = min(max(current + steps, 0), all.count - 1)
        return all[index]
    }

    private func segment(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FlowFont.chromeLabel)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? .white : FlowTheme.secondaryText(scheme))
                .padding(.horizontal, FlowSpacing.m)
                .frame(minHeight: 34)
                .background(Capsule().fill(isSelected ? FlowTheme.accentFill : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ newPane: MapTodayScreen.Pane) {
        guard newPane != pane else { return }
        animated { pane = newPane }
    }

    private func animated(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86), body)
        }
    }
}
