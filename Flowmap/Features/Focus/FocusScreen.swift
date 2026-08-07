import SwiftData
import SwiftUI

/// The signature screen: today's plan as a clock-like ring, one task at a time.
struct FocusScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    @State private var page: FocusCardPage = .today
    @State private var cardDetent: FocusCardDetent = .rest
    @State private var visibilityHUD: String?
    @State private var showingDurationPicker = false
    /// Set only while a pinch is in progress: the live, fractional position on
    /// `FocusWheelGeometry`'s zoom axis. `nil` means the dial is settled on the
    /// persisted mode, so nothing extra is ever stored.
    @State private var liveZoom: Double?
    /// Where the pinch in progress started from.
    @State private var pinchBaseZoom: Double = 0
    /// Decision 13: the countdown is tappable to hide, with a `◷` button in
    /// its place to bring it back. Deliberately not persisted — a hidden
    /// timer is a "let me look at the dial" moment, not a setting.
    @State private var isTimerHidden = false

    /// Redraws the countdown once a second without touching the store.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                FlowTheme.background(scheme).ignoresSafeArea()

                if hasAnythingToShow {
                    wheelLayer(in: proxy.size)
                    cardLayer(in: proxy.size)
                } else {
                    completionState
                }

                if let hud = visibilityHUD {
                    hudBadge(hud)
                }

                if let transition = flow?.focusEngine.pendingTransition {
                    transitionBanner(transition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .flowDialogOverlay(isPresented: pendingGate != nil) { gateDialog }
        .onReceive(ticker) { date in
            flow?.tick(date)
        }
        // Feedback task 17: the checklist is the task's externalised working
        // memory, so the card opens straight to it whenever a task is
        // active. Keyed on the id, not the task object, so the user's own
        // mid-session swipe away from Subtasks is respected until the
        // active task itself actually changes.
        .onAppear {
            page = activeTask == nil ? .today : .subtasks
            cardDetent = activeTask == nil ? .rest : .open
        }
        .onChange(of: activeTask?.id) { _, newID in
            page = newID == nil ? .today : .subtasks
            if newID != nil { cardDetent = .open }
        }
        #if os(macOS)
        .toolbar { toolbarContent }
        #endif
        .sheet(isPresented: $showingDurationPicker) {
            FocusDurationPicker { minutes, task in
                _ = task.map { flow?.focusEngine.start(task: $0, minutes: minutes) }
                    ?? flow?.focusEngine.startFreeFocus(minutes: minutes)
                showingDurationPicker = false
            }
        }
        // The mock's screen title is a small centred word inside the content,
        // not the system navigation bar — this tab keeps no back button to lose.
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: - Derived state

    private var engine: FocusEngine? { flow?.focusEngine }
    private var now: Date { flow?.now ?? Date() }
    private var pendingGate: PendingGate? { engine?.pendingGate }

    private var session: FocusSession? { engine?.activeSession }

    private var queue: [TaskSegment] { engine?.queue(for: now) ?? [] }

    private var activeSegment: TaskSegment? {
        session?.segment ?? engine?.currentSegment(at: now)
    }

    private var activeTask: FlowTask? { session?.task ?? activeSegment?.task }

    private var hasAnythingToShow: Bool { session != nil || !queue.isEmpty }

    private var visibility: WheelVisibility {
        let stored = flow?.settings.wheelVisibility ?? .two
        // A previous bowl build could persist `5M`; the current circular dial
        // has no visible 5M state, so fall back to the nearest exposed zoom.
        return WheelVisibility.carouselModes.contains(stored) ? stored : .one
    }

    /// The dial's place on the continuous zoom axis: the live pinch value while
    /// the fingers are down, otherwise the settled mode's own index.
    private var zoom: Double {
        liveZoom ?? FocusWheelGeometry.carouselZoom(for: visibility)
    }

    /// Which chip reads as selected. Mid-pinch that is the mode the dial would
    /// settle on if the fingers lifted now, so the row keeps stating the
    /// current state instead of a stale one.
    private var highlightedMode: WheelVisibility {
        liveZoom.map { FocusWheelGeometry.settledCarouselMode(forZoom: $0) } ?? visibility
    }

    /// The active task first, then the queue behind it, each carrying the
    /// clock time it starts. The time-based bowl needs every scheduled
    /// segment, not just the next handful — it crops what's actually drawn
    /// by visible angle, not by a task-count cap (`focus-wheel-spec.md` §2),
    /// so nothing here truncates by `visibility` any more.
    private var wheelItems: [WheelItem] {
        var ordered: [(task: FlowTask?, minutes: Int, id: UUID, start: Date)] = []

        if let task = activeTask {
            let minutes = session.map { Int(($0.plannedSeconds / 60).rounded()) }
                ?? activeSegment?.durationMinutes
                ?? task.estimatedMinutes
            let start = activeSegment?.startDate ?? session?.startedAt ?? now
            ordered.append((task, minutes, activeSegment?.id ?? task.id, start))
        }

        for segment in queue where segment.id != activeSegment?.id {
            guard segment.startDate >= now || segment.id != activeSegment?.id else { continue }
            ordered.append((segment.task, segment.durationMinutes, segment.id, segment.startDate))
        }

        // Free focus with no task still deserves a ring to watch.
        if ordered.isEmpty, let session {
            ordered.append((nil, Int((session.plannedSeconds / 60).rounded()), session.id, session.startedAt))
        }

        return ordered.enumerated().map { index, entry in
            WheelItem(
                id: entry.id,
                title: entry.task?.title ?? "Focus",
                iconName: entry.task?.iconName ?? "timer",
                colour: entry.task?.colour ?? .violet,
                minutes: entry.minutes,
                isActive: index == 0,
                startMinutes: minutesFromMidnight(entry.start)
            )
        }
    }

    /// Minutes since midnight on the day `date` falls on — the common time
    /// axis the bowl places every segment along (`focus-wheel-spec.md` §2's
    /// `start`/`nowW` units). This is unit conversion, not geometry:
    /// `FocusWheelGeometry` still does every angular computation from the
    /// raw minute value returned here.
    private func minutesFromMidnight(_ date: Date) -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return date.timeIntervalSince(start) / 60
    }

    private var nowMinutes: Double { minutesFromMidnight(now) }

    private var progress: Double { session?.progress(at: now) ?? 0 }

    // MARK: - Layers

    /// The wheel sits above the card with a real gap: the card's resting height
    /// plus a spacing constant is reserved, so the two can never touch at rest.
    private func wheelLayer(in size: CGSize) -> some View {
        let reserved = cardDetent.height(for: size.height) + FlowSpacing.wheelCardGap
        // The title bar and centre readout sit above the dial, so reserve their
        // stable space alongside the card's. There is no transient hint row:
        // the dial itself is the visual instruction.
        let chromeReserve = FlowSpacing.xxxl * 2 + FlowSpacing.xl
        let dialWidth = size.width - FlowSpacing.screen * 2
        // Collapsing the card is a request to see the dial, so its ceiling
        // lifts with it — otherwise the freed height is just empty screen.
        let dialCeiling: CGFloat = cardDetent == .hidden ? 500 : 430
        // The ring is the screen's visual anchor. Size its container from the
        // available width first, then let the checklist card occupy the lower
        // surface; reserving the open card before sizing the ring made the
        // circular dial shrink by roughly a quarter at the exact moment focus
        // began.
        let widthSizedDialHeight = dialWidth + 44
        let dialHeight = max(
            120,
            min(dialCeiling, max(widthSizedDialHeight, size.height - reserved - chromeReserve))
        )

        return VStack(spacing: FlowSpacing.m) {
            titleBar
            Text("Pinch to zoom")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .accessibilityHidden(true)
            #if !os(macOS)
            visibilityPill
            #endif

            ZStack {
                FocusWheelView(
                    items: wheelItems,
                    progress: progress,
                    activeID: wheelItems.first?.id,
                    nowMinutes: nowMinutes,
                    zoom: zoom,
                    isZooming: liveZoom != nil
                )
                focusDialCentre
            }
            .frame(width: dialWidth, height: dialHeight)

            Spacer(minLength: FlowSpacing.wheelCardGap)
        }
        .padding(.top, FlowSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if !os(macOS)
        .gesture(pinchGesture)
        #endif
    }

    /// The reference's top row is deliberately quiet: one stable menu button
    /// and one appearance control, with the dial's zoom control below it.
    private var titleBar: some View {
        HStack {
            #if !os(macOS)
            optionsButton
            Spacer()
            cornerButton(systemImage: appearanceSymbol, label: "Change appearance, currently \(flow?.settings.appearance.displayName ?? "System")") {
                cycleAppearance()
            }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    #if !os(macOS)
    private var optionsButton: some View {
        Button { showingDurationPicker = true } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(width: 58, height: 58)
                .background(Circle().fill(FlowTheme.surface(scheme)))
                .overlay(Circle().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
                .shadow(color: FlowTheme.shadow(scheme), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open focus options")
        .accessibilityValue(visibility.announcement)
        .accessibilityHint("Choose a focus duration")
    }

    /// The zoom state is always visible, as in the reference, so the user
    /// never has to remember which level the dial is using.
    private var visibilityPill: some View {
        HStack(spacing: FlowSpacing.s) {
            Text("View:")
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .fixedSize()
            ForEach(WheelVisibility.carouselModes, id: \.self) { mode in
                if mode == .all {
                    Rectangle()
                        .fill(FlowTheme.separator(scheme))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, FlowSpacing.xs)
                }
                Button {
                    setVisibility(mode)
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 16, weight: mode == highlightedMode ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(mode == highlightedMode ? .white : FlowTheme.primaryText(scheme))
                        .frame(width: mode == .fiveMinute ? 38 : 34, height: 34)
                        .fixedSize()
                        .background {
                            if mode == highlightedMode { Circle().fill(FlowTheme.accent) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus-wheel-mode-\(mode.rawValue)")
                .accessibilityLabel(mode.announcement)
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.xs)
        .background(Capsule().fill(FlowTheme.surface(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
        .shadow(color: FlowTheme.shadow(scheme), radius: 8, y: 3)
        .frame(minWidth: 250)
        .accessibilityElement(children: .contain)
    }

    private var appearanceSymbol: String {
        switch flow?.settings.appearance ?? .system {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// Cycles the existing appearance setting rather than adding a new one —
    /// the mock's corner button gets a home, no new behaviour is invented.
    private func cycleAppearance() {
        guard let flow else { return }
        let modes = AppearanceMode.allCases
        let index = modes.firstIndex(of: flow.settings.appearance) ?? 0
        flow.settings.appearance = modes[(index + 1) % modes.count]
        try? context.save()
    }

    /// The mock draws these small; the tap target is grown to 44pt around
    /// the artwork instead of scaling the artwork up.
    private func cornerButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: 34, height: 34)
                .background(Circle().fill(FlowTheme.surface(scheme)))
                .overlay(Circle().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
    #endif

    private func cardLayer(in size: CGSize) -> some View {
        FocusTaskCard(
            queue: queue,
            activeTask: activeTask,
            activeSegmentID: activeSegment?.id,
            onSelect: { segment in
                _ = engine?.start(segment: segment, now: now)
            },
            page: $page,
            detent: $cardDetent
        )
        .frame(height: size.height)
        .allowsHitTesting(true)
    }

    // MARK: - Centre

    /// The dial keeps one calm, tactile control in the centre. The task icon
    /// belongs to the active ring block; repeating it here made the focus
    /// state compete with itself and did not exist in the chosen reference.
    private var focusDialCentre: some View {
        Button {
            if session == nil { startBestAvailable() }
            else { engine?.togglePause(now: now) }
        } label: {
            Image(systemName: playPauseSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FlowTheme.accentText(scheme))
                .frame(width: FlowControlSize.hero, height: FlowControlSize.hero)
                .background(neumorphicDisc())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playPauseLabel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -16)
        .accessibilityElement(children: .contain)
    }

    /// The running clock is the focal point. The task name belongs on the
    /// dial itself, so the centre stays quiet and leaves the arc unobscured.
    private var centreContent: some View {
        VStack(spacing: FlowSpacing.s) {
            if session == nil {
                HStack(spacing: FlowSpacing.xs) {
                    Image(systemName: activeTask?.iconName ?? "timer")
                        .font(.system(size: 17, weight: .regular))
                    Text(activeTask?.title ?? "Ready when you are")
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(FlowTheme.primaryText(scheme))
            }

            countdownSlot

            if session != nil {
                Text(sessionEndLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            controls.padding(.top, FlowSpacing.xs)
        }
    }

    /// Decision 13: the countdown hides on a tap, and a `◷` button takes its
    /// place to bring it back — so the dial can be watched uncluttered.
    @ViewBuilder
    private var countdownSlot: some View {
        if isTimerHidden {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isTimerHidden = false }
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .frame(width: FlowControlSize.utility, height: FlowControlSize.utility)
                    .background(Circle().fill(FlowTheme.surface(scheme)))
                    .overlay(Circle().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            // The 38pt disc sits under the HIG's 44pt floor, so the target is
            // grown around it rather than the disc scaled up.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Show timer")
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isTimerHidden = true }
            } label: {
                Text(countdownDisplayText)
                    .font(.system(size: session == nil ? 24 : 38, weight: .bold, design: .rounded))
                .foregroundStyle(FlowTheme.accentText(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(countdownAccessibilityLabel)
            .accessibilityHint("Hides the timer")
        }
    }

    private var controls: some View {
        HStack(spacing: FlowSpacing.l) {
            if session != nil {
                circularControlButton(systemImage: "forward.end", label: "Skip this task and requeue the rest") {
                    engine?.skipCurrentTask(now: now)
                }
            }

            Button {
                if session == nil {
                    startBestAvailable()
                } else {
                    engine?.togglePause(now: now)
                }
            } label: {
                Image(systemName: playPauseSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FlowTheme.accentText(scheme))
                    .frame(width: FlowControlSize.hero, height: FlowControlSize.hero)
                    .background(neumorphicDisc())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playPauseLabel)

        }
    }

    /// The mock's near-neumorphic control: a warm shadow cast below, a light
    /// highlight caught above, on a plain white disc rather than a flat fill.
    private func neumorphicDisc() -> some View {
        Circle()
            .fill(FlowTheme.surface(scheme))
            .shadow(color: FlowTheme.shadow(scheme), radius: 6, x: 0, y: 4)
            .shadow(color: FlowTheme.raisedHighlight(scheme), radius: 4, x: 0, y: -3)
    }

    /// Skip/complete on either side of the play/pause button — the same
    /// neumorphic disc, a size down.
    private func circularControlButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                .background(neumorphicDisc())
        }
        .buttonStyle(.plain)
        // FlowControlSize.secondary (42pt) draws under the HIG's 44pt floor;
        // the tap target is grown around the disc rather than the disc scaled up.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }

    /// Remaining time in whole minutes, rounded up so it still reads "1 min"
    /// with seconds left rather than dropping to zero early.
    private var countdownMinutesText: String {
        let seconds: Double
        if let session {
            seconds = session.remainingSeconds(at: now)
        } else if let segment = activeSegment {
            seconds = Double(segment.durationMinutes) * 60
        } else {
            seconds = Double(flow?.settings.defaultFreeFocusMinutes ?? 30) * 60
        }
        return "\(Int((seconds / 60).rounded(.up)))"
    }

    private var countdownAccessibilityLabel: String {
        if let session {
            return DurationFormatter.spokenCountdown(seconds: session.remainingSeconds(at: now))
        }
        if let segment = activeSegment {
            return "Ready to start, \(DurationFormatter.spoken(minutes: segment.durationMinutes))"
        }
        return "No task running"
    }

    private var countdownDisplayText: String {
        if let session { return session.countdownLabel(at: now) }
        return "(countdownMinutesText) min"
    }

    private var sessionEndLabel: String {
        if let segment = activeSegment {
            return "Ends \(DurationFormatter.time(segment.endDate))"
        }
        guard let session else { return "" }
        let end = session.startedAt.addingTimeInterval(session.plannedSeconds + session.accumulatedPausedSeconds)
        return "Ends \(DurationFormatter.time(end))"
    }

    private var playPauseSymbol: String {
        guard let session else { return "play.fill" }
        return session.isPaused ? "play.fill" : "pause.fill"
    }

    private var playPauseLabel: String {
        guard let session else { return "Start focus" }
        return session.isPaused ? "Resume" : "Pause"
    }

    private func startBestAvailable() {
        if let segment = activeSegment {
            _ = engine?.start(segment: segment, now: now)
        } else {
            showingDurationPicker = true
        }
    }

    // MARK: - Empty and transition

    private var completionState: some View {
        VStack(spacing: FlowSpacing.l) {
            FlowEmptyState(
                symbol: "checkmark.circle",
                title: "That's the plan done",
                message: completedSummary
            )
            SecondaryActionButton("Start a focus session", systemImage: "timer") {
                showingDurationPicker = true
            }
        }
        .padding(FlowSpacing.screen)
    }

    private var completedSummary: String {
        let tasks = (try? context.fetch(FetchDescriptor<FlowTask>())) ?? []
        let calendar = Calendar.current
        let completed = tasks.count {
            guard let date = $0.completedAt else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }
        let carried = tasks.count {
            guard let date = $0.lastCarriedAt else { return false }
            return calendar.isDate(date, inSameDayAs: now)
        }
        var parts: [String] = ["\(completed) task\(completed == 1 ? "" : "s") completed today"]
        if carried > 0 { parts.append("\(carried) carried to a later slot") }
        return parts.joined(separator: " · ")
    }

    /// Renders the compulsory planning gate or the lighter clock-in modal,
    /// whichever `FocusEngine` decided this segment/task needs. Resolving
    /// either calls back into the engine, which is the only thing that may
    /// start the session it was blocking.
    @ViewBuilder
    private var gateDialog: some View {
        if let pendingGate {
            switch pendingGate.kind {
            case .planGate:
                PlanGateDialog(task: pendingGate.task) {
                    _ = engine?.resolveGate(now: now)
                }
            case .clockIn:
                ClockInDialog(task: pendingGate.task) {
                    _ = engine?.resolveGate(now: now)
                }
            }
        }
    }

    private func transitionBanner(_ transition: FocusTransition) -> some View {
        VStack {
            Spacer()
            FlowBanner(
                text: transition.bannerText,
                actions: bannerActions(transition),
                onDismiss: { engine?.pendingTransition = nil }
            )
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.xxxl * 2)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func bannerActions(_ transition: FocusTransition) -> [(title: String, handler: () -> Void)] {
        guard let requeue = transition.requeue else {
            guard let taskID = transition.improvableTaskID else { return [] }
            return [("Improve later", {
                _ = engine?.parkImprovement(for: taskID, now: now)
            })]
        }
        var actions: [(String, () -> Void)] = [
            ("Undo", { engine?.undoRequeue(requeue) }),
            ("Done", { engine?.completeFromBanner(requeue) }),
        ]
        if transition.canExtend {
            actions.append(("Add 15M now", {
                engine?.undoRequeue(requeue)
                if let task = (try? context.fetch(FetchDescriptor<FlowTask>()))?
                    .first(where: { $0.id == requeue.taskID }) {
                    _ = engine?.start(task: task, minutes: 15, now: now)
                }
            }))
        }
        return actions.map { (title: $0.0, handler: $0.1) }
    }

    private func hudBadge(_ text: String) -> some View {
        Text(text)
            .font(FlowFont.secondary.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, FlowSpacing.l)
            .padding(.vertical, FlowSpacing.s)
            .background(Capsule().fill(FlowTheme.popoverSurface))
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Visibility

    private func setVisibility(_ new: WheelVisibility) {
        guard let flow, flow.settings.wheelVisibility != new else { return }
        flow.settings.wheelVisibility = new
        try? context.save()
        withAnimation(.easeOut(duration: 0.2)) { visibilityHUD = new.announcement }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeIn(duration: 0.25)) { visibilityHUD = nil }
        }
    }

    #if !os(macOS)
    /// Pinching zooms the ring live: it grows and shrinks under the fingers,
    /// through the layouts between the four views, and settles on the nearest
    /// one when they lift. Spreading reveals more of the day; pinching narrows
    /// the focus. The mapping and the settle both live in `FocusWheelGeometry`,
    /// so the gesture and the visible chips can never drift onto different mode
    /// lists — and the chips remain the tap alternative the HIG asks for, since
    /// a custom gesture must never be the only way to reach a state.
    ///
    /// Nothing is persisted and no HUD fires until release: a per-frame write
    /// would announce three modes on the way to the one that was wanted.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if liveZoom == nil {
                    pinchBaseZoom = FocusWheelGeometry.carouselZoom(for: visibility)
                }
                liveZoom = FocusWheelGeometry.carouselZoom(
                    base: pinchBaseZoom,
                    magnification: value.magnification
                )
            }
            .onEnded { value in
                let settled = FocusWheelGeometry.settledCarouselMode(
                    forZoom: FocusWheelGeometry.carouselZoom(
                        base: pinchBaseZoom,
                        magnification: value.magnification
                    )
                )
                liveZoom = nil
                setVisibility(settled)
            }
    }
    #endif

    // iPhone shows the same picker as the glass chip row under the title
    // (see `visibilityChips`); this toolbar exists only for macOS's window chrome.
    #if os(macOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Visible tasks", selection: Binding(
                get: { visibility },
                set: { setVisibility($0) }
            )) {
                ForEach(WheelVisibility.carouselModes, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .help("How many tasks the wheel shows at once")
        }
    }
    #endif
}

/// Duration chooser for a focus session with no task attached.
struct FocusDurationPicker: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FlowTask.sortOrder) private var tasks: [FlowTask]

    /// 30 minutes is the free-focus default; 15 remains a preset.
    private let presets = [15, 25, 30, 45, 60]

    @State private var minutes: Int = 30
    @State private var selectedTask: FlowTask?

    let onStart: (Int, FlowTask?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            Text("Focus")
                .font(FlowFont.screenTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))

            Text("Choose a duration")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))

            Text("\(minutes) MINS")
                .font(FlowFont.countdown)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityLabel(DurationFormatter.spoken(minutes: minutes))

            HStack(spacing: FlowSpacing.s) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        minutes = preset
                    } label: {
                        Text(DurationFormatter.compact(minutes: preset))
                            .font(FlowFont.secondary.weight(.semibold))
                            .padding(.horizontal, FlowSpacing.m)
                            .padding(.vertical, FlowSpacing.s)
                            .background(
                                Capsule().fill(
                                    preset == minutes
                                        ? FlowTheme.accent.opacity(0.2)
                                        : FlowTheme.separator(scheme).opacity(0.6)
                                )
                            )
                            .foregroundStyle(
                                preset == minutes ? FlowTheme.accent : FlowTheme.primaryText(scheme)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DurationFormatter.spoken(minutes: preset))
                }
            }

            if !openTasks.isEmpty {
                Picker("Task (optional)", selection: $selectedTask) {
                    Text("No task").tag(FlowTask?.none)
                    ForEach(openTasks) { task in
                        Text(task.title).tag(FlowTask?.some(task))
                    }
                }
                .pickerStyle(.menu)
            }

            PrimaryActionButton("Start focus", systemImage: "play.fill") {
                onStart(minutes, selectedTask)
                dismiss()
            }

            Spacer(minLength: 0)
        }
        .padding(FlowSpacing.screen)
        .frame(minWidth: 320, minHeight: 420)
        .background(FlowTheme.background(scheme))
        .onAppear {
            minutes = flow?.settings.defaultFreeFocusMinutes ?? 30
        }
    }

    private var openTasks: [FlowTask] {
        tasks.filter { $0.status.isOpen }
    }
}
