import SwiftData
import SwiftUI

/// The signature screen: today's plan as a clock-like ring, one task at a time.
struct FocusScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: FocusCardPage = .today
    @State private var cardExpansion: Double = 0
    @State private var visibilityHUD: String?
    @State private var showingDurationPicker = false
    @State private var pinchBaseline: WheelVisibility = .two

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
        .onReceive(ticker) { date in
            flow?.tick(date)
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

    private var session: FocusSession? { engine?.activeSession }

    private var queue: [TaskSegment] { engine?.queue(for: now) ?? [] }

    private var activeSegment: TaskSegment? {
        session?.segment ?? engine?.currentSegment(at: now)
    }

    private var activeTask: FlowTask? { session?.task ?? activeSegment?.task }

    private var hasAnythingToShow: Bool { session != nil || !queue.isEmpty }

    private var visibility: WheelVisibility { flow?.settings.wheelVisibility ?? .two }

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
        let reserved = FocusTaskCard.restingHeight(for: size.height) + FlowSpacing.wheelCardGap
        // The title bar and the centre readout now sit above the dial rather
        // than inside it, so both need their own reserve alongside the card's.
        let chromeReserve = FlowSpacing.xxxl * 2 + FlowSpacing.xl
        let dialWidth = size.width - FlowSpacing.screen * 2
        let dialHeight = max(120, min(190, size.height - reserved - chromeReserve))

        return VStack(spacing: FlowSpacing.m) {
            titleBar
            centreContent

            Group {
                if visibility == .all {
                    FocusWheelOverviewView(
                        items: wheelItems,
                        isSessionActive: session != nil,
                        centreCountdownText: countdownMinutesText,
                        centreCountdownAccessibilityLabel: countdownAccessibilityLabel
                    )
                } else {
                    FocusWheelView(
                        items: wheelItems,
                        progress: progress,
                        activeID: wheelItems.first?.id,
                        nowMinutes: nowMinutes,
                        visibility: visibility
                    )
                }
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

    /// The mock's top row — a menu button, a quiet zoom hint, and an
    /// appearance button — with the "View" pill directly beneath it.
    private var titleBar: some View {
        VStack(spacing: FlowSpacing.m) {
            #if !os(macOS)
            HStack {
                cornerButton(systemImage: "line.3.horizontal", label: "Open focus options") {
                    showingDurationPicker = true
                }
                Spacer(minLength: FlowSpacing.s)
                Text("Pinch to zoom")
                    // Explicit 12pt: small but never below the HIG's 11pt floor.
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                Spacer(minLength: FlowSpacing.s)
                cornerButton(systemImage: appearanceSymbol, label: "Change appearance, currently \(flow?.settings.appearance.displayName ?? "System")") {
                    cycleAppearance()
                }
            }

            visibilityPill
            #endif
        }
    }

    #if !os(macOS)
    /// A single white pill reading "View: 1 2 3 | All", the selected number
    /// sitting inside a filled clay circle — not a segmented control.
    private var visibilityPill: some View {
        HStack(spacing: 2) {
            Text("View:")
                .font(FlowFont.chromeLabel)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .padding(.leading, FlowSpacing.s)

            ForEach(Array(WheelVisibility.allCases.enumerated()), id: \.element) { index, mode in
                if mode == .all {
                    Rectangle()
                        .fill(FlowTheme.separator(scheme))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                        .accessibilityHidden(true)
                }
                visibilityOption(mode)
            }
        }
        .padding(.vertical, FlowSpacing.xxs)
        .padding(.trailing, FlowSpacing.xs)
        .background(Capsule().fill(FlowTheme.surface(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func visibilityOption(_ mode: WheelVisibility) -> some View {
        let isSelected = mode == visibility
        return Button {
            setVisibility(mode)
        } label: {
            Text(mode.displayName)
                .font(FlowFont.chromeLabel)
                .foregroundStyle(isSelected ? .white : FlowTheme.secondaryText(scheme))
                .frame(width: 26, height: 26)
                .background(isSelected ? AnyView(Circle().fill(FlowTheme.accentFill)) : AnyView(Color.clear))
        }
        .buttonStyle(.plain)
        // The visible chip is smaller than the HIG's 44pt minimum, so the tap
        // target is grown around it rather than the artwork scaled up.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        // Reuses the same string the HUD shows on selection, so `5M` never
        // gets mislabelled as a task count here either (`WheelVisibility.announcement`).
        .accessibilityLabel(mode.announcement)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
            expansion: $cardExpansion
        )
        .frame(height: size.height)
        .allowsHitTesting(true)
    }

    // MARK: - Centre

    /// Icon and task name on one line, remaining minutes in clay beneath it —
    /// the mock's centre readout, still reading the live remaining time, just
    /// in whole minutes rather than a running clock.
    private var centreContent: some View {
        VStack(spacing: FlowSpacing.s) {
            HStack(spacing: FlowSpacing.xs) {
                Image(systemName: activeTask?.iconName ?? "timer")
                    .font(.system(size: 17, weight: .regular))
                Text(activeTask?.title ?? "Ready when you are")
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(FlowTheme.primaryText(scheme))

            (
                Text(countdownMinutesText).font(.system(size: 22, weight: .bold, design: .rounded))
                    + Text(" min").font(.system(size: 13, weight: .semibold, design: .rounded))
            )
            .foregroundStyle(FlowTheme.accentText(scheme))
            .accessibilityLabel(countdownAccessibilityLabel)

            controls.padding(.top, FlowSpacing.xs)
        }
    }

    private var controls: some View {
        VStack(spacing: FlowSpacing.m) {
            // Decorative badge, not a button: the task name right above it
            // already reaches VoiceOver, so this stays out of its way.
            Image(systemName: activeTask?.iconName ?? "book.closed")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: FlowControlSize.utility, height: FlowControlSize.utility)
                .background(neumorphicDisc())
                .accessibilityHidden(true)

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

                if session != nil {
                    circularControlButton(systemImage: "checkmark", label: "Complete this task") {
                        engine?.completeCurrentTask(now: now)
                    }
                }
            }
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
        guard let requeue = transition.requeue else { return [] }
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
    /// Pinching changes how much of the day the ring reveals.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.08)
            .onChanged { value in
                let modes = WheelVisibility.allCases
                guard let baseIndex = modes.firstIndex(of: pinchBaseline) else { return }
                // Spreading reveals more of the day; pinching narrows the focus.
                let step = value.magnification > 1 ? 1 : -1
                let target = modes[min(modes.count - 1, max(0, baseIndex + step))]
                setVisibility(target)
            }
            .onEnded { _ in pinchBaseline = visibility }
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
                ForEach(WheelVisibility.allCases, id: \.self) { mode in
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
