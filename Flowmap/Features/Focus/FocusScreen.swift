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
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingDurationPicker) {
            FocusDurationPicker { minutes, task in
                _ = task.map { flow?.focusEngine.start(task: $0, minutes: minutes) }
                    ?? flow?.focusEngine.startFreeFocus(minutes: minutes)
                showingDurationPicker = false
            }
        }
        .navigationTitle("Focus")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
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

    /// The active task first, then the queue behind it.
    private var wheelItems: [WheelItem] {
        var ordered: [(FlowTask?, Int, UUID)] = []

        if let task = activeTask {
            let minutes = session.map { Int(($0.plannedSeconds / 60).rounded()) }
                ?? activeSegment?.durationMinutes
                ?? task.estimatedMinutes
            ordered.append((task, minutes, activeSegment?.id ?? task.id))
        }

        for segment in queue where segment.id != activeSegment?.id {
            guard segment.startDate >= now || segment.id != activeSegment?.id else { continue }
            ordered.append((segment.task, segment.durationMinutes, segment.id))
        }

        // Free focus with no task still deserves a ring to watch.
        if ordered.isEmpty, let session {
            ordered.append((nil, Int((session.plannedSeconds / 60).rounded()), session.id))
        }

        let count = FocusWheelGeometry.visibleCount(for: visibility, queueCount: ordered.count)
        return ordered.prefix(count).enumerated().map { index, entry in
            WheelItem(
                id: entry.2,
                title: entry.0?.title ?? "Focus",
                iconName: entry.0?.iconName ?? "timer",
                colour: entry.0?.colour ?? .violet,
                minutes: entry.1,
                isActive: index == 0
            )
        }
    }

    private var progress: Double { session?.progress(at: now) ?? 0 }

    // MARK: - Layers

    /// The wheel sits above the card with a real gap: the card's resting height
    /// plus a spacing constant is reserved, so the two can never touch at rest.
    private func wheelLayer(in size: CGSize) -> some View {
        let reserved = FocusTaskCard.restingHeight(for: size.height) + FlowSpacing.wheelCardGap
        let available = max(160, size.height - reserved - FlowSpacing.xxl)
        let diameter = min(available, size.width - FlowSpacing.screen * 2)

        return VStack(spacing: 0) {
            ZStack {
                FocusWheelView(
                    items: wheelItems,
                    progress: progress,
                    activeID: wheelItems.first?.id
                )
                .frame(width: diameter, height: diameter)

                centreContent
                    .frame(width: diameter * 0.52)
            }
            .frame(width: diameter, height: diameter)
            .padding(.top, FlowSpacing.l)

            Spacer(minLength: FlowSpacing.wheelCardGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if !os(macOS)
        .gesture(pinchGesture)
        #endif
    }

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

    private var centreContent: some View {
        VStack(spacing: FlowSpacing.xs) {
            Image(systemName: activeTask?.iconName ?? "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle((activeTask?.colour ?? .violet).onSoft)

            // Before anything is running, show the time the next block will take
            // rather than an empty placeholder — the number the user is about to
            // commit to is more useful than a dash.
            Text(countdownText)
                .font(FlowFont.countdown)
                .foregroundStyle(
                    session == nil
                        ? FlowTheme.secondaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
                .accessibilityLabel(countdownAccessibilityLabel)

            Text(activeTask?.title ?? "Ready when you are")
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let segment = activeSegment {
                Text(DurationFormatter.timeRange(from: segment.startDate, to: segment.endDate))
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            controls.padding(.top, FlowSpacing.s)
        }
    }

    private var controls: some View {
        VStack(spacing: FlowSpacing.s) {
            Button {
                if session == nil {
                    startBestAvailable()
                } else {
                    engine?.togglePause(now: now)
                }
            } label: {
                Image(systemName: playPauseSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(FlowTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playPauseLabel)

            if session != nil {
                HStack(spacing: FlowSpacing.l) {
                    Button {
                        engine?.completeCurrentTask(now: now)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(FlowFont.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .accessibilityLabel("Complete this task")

                    Button {
                        engine?.skipCurrentTask(now: now)
                    } label: {
                        Label("Skip", systemImage: "forward.end")
                            .font(FlowFont.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .accessibilityLabel("Skip this task and requeue the rest")
                }
            }
        }
    }

    private var countdownText: String {
        if let session {
            return DurationFormatter.countdown(seconds: session.remainingSeconds(at: now))
        }
        if let segment = activeSegment {
            return DurationFormatter.countdown(seconds: Double(segment.durationMinutes) * 60)
        }
        return DurationFormatter.countdown(
            seconds: Double(flow?.settings.defaultFreeFocusMinutes ?? 30) * 60
        )
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
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
        #else
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Visible tasks", selection: Binding(
                    get: { visibility },
                    set: { setVisibility($0) }
                )) {
                    ForEach(WheelVisibility.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "circle.dashed")
            }
            .accessibilityLabel("Visible tasks")
        }
        #endif
    }
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
