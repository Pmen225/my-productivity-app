import SwiftData
import SwiftUI

/// The signature screen: today's plan as a clock-like ring, one task at a time.
struct FocusScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read for the idle screen's inbox count only — the same
    /// `SmartView.inbox` filter the Plan tab's badge uses, so the two
    /// numbers can never disagree.
    @Query private var allTasks: [FlowTask]

    /// Task 58 (founder ruling 2026-08-08, option B): the queue lives in a
    /// native sheet the always-visible `FocusNowBar` opens on tap. It never
    /// self-presents — see the removed auto-open note below.
    @State private var queueSheetShown = false
    @State private var visibilityHUD: String?
    @State private var showingDurationPicker = false
    /// Set only while a pinch is in progress: the live, fractional position on
    /// `FocusWheelGeometry`'s zoom axis. `nil` means the dial is settled on the
    /// persisted mode, so nothing extra is ever stored.
    @State private var liveZoom: Double?
    /// Where the pinch in progress started from.
    @State private var pinchBaseZoom: Double = 0
    /// Set only while a close-up pinch is in progress: the live magnification
    /// about the pointer. `nil` means the dial is showing the settled factor.
    @State private var liveMagnify: Double?
    /// Where the close-up pinch in progress started from.
    @State private var pinchBaseMagnify: Double = 1
    /// The re-forming style's live swell, `1` at rest. Rendering only.
    @State private var dialScale: Double = 1
    /// Decision 13: the countdown is tappable to hide, with a `◷` button in
    /// its place to bring it back. Deliberately not persisted — a hidden
    /// timer is a "let me look at the dial" moment, not a setting.
    @State private var isTimerHidden = false
    /// Degrees of time-travel preview while a one-finger drag is peeking ahead,
    /// springing back to zero on release. Never persisted: it is a look, not a
    /// change of state.
    @State private var previewOffset: Double = 0
    /// Where the drag in progress started from, so the ring follows the finger
    /// from wherever it already was rather than jumping to zero.
    @State private var dragBaseOffset: Double = 0
    @State private var isDragging = false
    /// The dial's drawn radius, recorded when it is laid out. The drag maps
    /// finger travel to degrees against it, and a tab that is off screen has
    /// no radius to map against.
    @State private var dialRadius: CGFloat = 0
    /// A tab bar keeps every tab alive, so "is this view built" is not the same
    /// question as "is the user looking at it". Haptics must only fire for the
    /// second one.
    @State private var isOnScreen = false
    /// The "Pinch to zoom" caption idle-fades once the founder has had a
    /// moment to read it (DESIGN_ANALYSIS.md: chrome idle-fades ~3.5s).
    /// Opacity-only — the row keeps its space so nothing else on the screen
    /// moves when it goes.
    @State private var hintVisible = true

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
                    emptyLayer
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
        .onAppear {
            isOnScreen = true
        }
        .onDisappear { isOnScreen = false }
        // Changing the style in Settings while a session runs must land on the
        // new style's rest state, not on half of the old one's gesture.
        .onChange(of: zoomStyle) { _, _ in
            liveZoom = nil
            liveMagnify = nil
            dialScale = 1
            previewOffset = 0
            isDragging = false
        }
        // Four detents, no more. Each is a discrete event the eye can already
        // see happening, which is what stops the wheel from buzzing at the
        // reader (HIG: short haptics for discrete events, never a running one).
        // Every trigger is derived state, so nothing here owns a timer.
        //
        // A pinch settling on a new level of detail.
        .sensoryFeedback(trigger: zoomDetent) { old, new in
            guard old != nil, new != nil else { return nil }
            return .impact(weight: .medium)
        }
        // Each five-minute mark disappearing into the pointer. A paused session
        // freezes its remaining time, so the bucket stops moving and this
        // stays silent on its own.
        .sensoryFeedback(trigger: fiveMinuteMark) { old, new in
            guard let old, let new, new < old else { return nil }
            return .impact(weight: .light)
        }
        // The handover to the next task: the one moment worth a firmer knock.
        .sensoryFeedback(trigger: isOnScreen ? activeSegment?.id : nil) { old, new in
            guard old != nil, new != nil else { return nil }
            return .impact(weight: .heavy)
        }
        // A block boundary passing the pointer while the finger is dragging,
        // so peeking ahead is counted out rather than just watched.
        .sensoryFeedback(trigger: previewIndex) { old, new in
            guard old != nil, new != nil else { return nil }
            return .impact(weight: .light)
        }
        #if os(macOS)
        .toolbar { toolbarContent }
        #endif
        .sheet(isPresented: $showingDurationPicker) {
            FocusDurationPicker { minutes in
                _ = flow?.focusEngine.startFreeFocus(minutes: minutes)
                showingDurationPicker = false
            }
        }
        // Task 58: attached to the screen's own body root, never to a nested
        // `Section` (CLAUDE.md trap — a `.sheet` on a view whose body roots at
        // `Section` never presents). macOS gets no sheet: its queue renders
        // inline instead (see `cardLayer`).
        #if !os(macOS)
        .sheet(isPresented: $queueSheetShown) {
            FocusQueueSheet(
                queue: queue,
                activeTask: activeTask,
                activeSegmentID: activeSegment?.id
            )
        }
        #endif
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

    /// A build that persisted the removed `5M` state stores a raw string the
    /// enum can no longer decode, so `AppSettings`' own `?? .two` fallback
    /// already resolves it — nothing left to translate here.
    private var visibility: WheelVisibility {
        flow?.settings.wheelVisibility ?? .two
    }

    /// Which of the two things a pinch does. The close-up is the default: the
    /// founder's ruling is that zooming in should hide the rest of the wheel,
    /// not re-form it to keep the whole circle on screen.
    private var zoomStyle: WheelZoomStyle {
        flow?.settings.wheelZoomStyle ?? .magnify
    }

    /// The dial's place on the continuous zoom axis: the live pinch value while
    /// the fingers are down, otherwise the settled mode's own index.
    ///
    /// The close-up style pins this to the whole-day layout — there the pinch
    /// drives `magnification` instead, so the ring keeps one set of widths and
    /// is simply drawn larger.
    private var zoom: Double {
        if zoomStyle == .magnify { return FocusWheelGeometry.carouselZoom(for: .all) }
        return liveZoom ?? FocusWheelGeometry.carouselZoom(for: visibility)
    }

    /// How far the close-up is magnified about the pointer: the live pinch
    /// value while the fingers are down, otherwise the factor it settled on.
    /// Always `1` in the re-forming style, which draws the whole circle.
    private var magnification: Double {
        guard zoomStyle == .magnify else { return 1 }
        return liveMagnify ?? FocusWheelGeometry.clampMagnify(flow?.settings.wheelMagnifyFactor ?? 1)
    }

    /// What a settle is worth knocking for in each style: the level landed on
    /// in the re-forming style, the doubling crossed in the close-up. One
    /// derived value so both styles share the one existing haptic.
    private var zoomDetent: String? {
        guard isOnScreen else { return nil }
        if zoomStyle == .magnify {
            return "m\(FocusWheelGeometry.magnifyHapticBucket(factor: magnification))"
        }
        return visibility.rawValue
    }

    /// The active task first, then the queue behind it, each carrying the
    /// clock time it starts. Every scheduled segment is passed on, not just
    /// the next handful: the dial decides what to draw from the zoom's own
    /// slice widths, so nothing here truncates by `visibility`.
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
    /// axis every segment carries (`focus-wheel-spec.md` §2's `start`/`nowW`
    /// units). This is unit conversion, not geometry:
    /// `FocusWheelGeometry` still does every angular computation from the
    /// raw minute value returned here.
    private func minutesFromMidnight(_ date: Date) -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return date.timeIntervalSince(start) / 60
    }

    private var nowMinutes: Double { minutesFromMidnight(now) }

    private var progress: Double { session?.progress(at: now) ?? 0 }

    /// Which five-minute mark the pointer is on, or `nil` when there is nothing
    /// running to count. A bucket rather than a time: the value only changes
    /// when a mark is actually consumed, so the feedback it drives cannot fire
    /// per frame however often the view is rebuilt.
    private var fiveMinuteMark: Int? {
        guard isOnScreen, let session, session.isRunning else { return nil }
        return Int(session.remainingSeconds(at: now) / 60) / 5
    }

    /// The block the pointer is reading during a time-travel drag, or `nil` when
    /// no drag is in progress — so the boundary detent is silent the rest of
    /// the time rather than firing as the queue re-plans underneath it.
    private var previewIndex: Int? {
        guard isOnScreen, isDragging else { return nil }
        return FocusWheelGeometry.carouselIndexAtPointer(
            zoom: zoom,
            durations: wheelItems.map(\.minutes),
            elapsed: progress,
            offset: previewOffset
        )
    }

    // MARK: - Layers

    /// The wheel sits above the card with a real gap: the card's resting height
    /// plus a spacing constant is reserved, so the two can never touch at rest.
    private func wheelLayer(in size: CGSize) -> some View {
        #if os(macOS)
        let reserved = Self.macQueueHeight(for: size.height) + FlowSpacing.wheelCardGap
        #else
        let reserved = FocusNowBar.height + FlowSpacing.wheelCardGap
        #endif
        // The title bar and centre readout sit above the dial, so reserve their
        // stable space alongside the card's. There is no transient hint row:
        // the dial itself is the visual instruction.
        let chromeReserve = FlowSpacing.xxxl * 2 + FlowSpacing.xl
        let dialWidth = size.width - FlowSpacing.screen * 2
        // Task 58: the slim now-bar frees far more height than the old card
        // ever did, so the wheel is the screen's one anchor now — a single
        // ceiling rather than a value that shifts with the card's detent.
        let dialCeiling: CGFloat = 500
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
                .opacity(hintVisible ? 1 : 0)
                .accessibilityHidden(true)
                .task {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(.easeOut(duration: 0.6)) {
                        hintVisible = false
                    }
                }

            ZStack {
                FocusWheelView(
                    items: wheelItems,
                    progress: progress,
                    activeID: wheelItems.first?.id,
                    nowMinutes: nowMinutes,
                    zoom: zoom,
                    isZooming: liveZoom != nil || liveMagnify != nil,
                    previewOffset: previewOffset,
                    magnification: magnification,
                    reformScale: dialScale
                )
                focusDialCentre
            }
            .frame(width: dialWidth, height: dialHeight)
            // The drag maps finger travel against the ring the user can see, so
            // it reads the dial's own radius rather than a second guess at it.
            .onAppear {
                dialRadius = FocusWheelGeometry.carouselDiameter(
                    in: CGSize(width: dialWidth, height: dialHeight)
                ) / 2
            }
            .onChange(of: dialHeight) { _, newHeight in
                dialRadius = FocusWheelGeometry.carouselDiameter(
                    in: CGSize(width: dialWidth, height: newHeight)
                ) / 2
            }
            // With the chips gone, this is VoiceOver's whole path to the zoom.
            // A custom gesture must never be the only way to reach a state.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Focus wheel zoom")
            .accessibilityValue(zoomStyle == .magnify ? magnifyAnnouncement : visibility.announcement)
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 1 : -1
                if zoomStyle == .magnify {
                    stepMagnify(delta)
                } else {
                    stepVisibility(delta)
                }
            }

            Spacer(minLength: FlowSpacing.wheelCardGap)
        }
        .padding(.top, FlowSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if !os(macOS)
        // Both, not one or the other. `MagnifyGesture` never begins on one
        // finger, so the drag owns the single-finger case on its own; an
        // `ExclusiveGesture` instead waits for a pinch that will never fail and
        // swallows the drag entirely (verified: the ring did not move under a
        // live finger). The drag bows out for itself while a pinch is live.
        .gesture(pinchGesture)
        .simultaneousGesture(timeTravelGesture)
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

    /// Task 58 (founder ruling 2026-08-08, option B): iPhone pins the slim
    /// `FocusNowBar` at the bottom, tapped to open `FocusQueueSheet`. macOS
    /// gets no sheet or bar — it renders the merged queue list inline, at the
    /// same bottom-aligned spot the old card sat in.
    private func cardLayer(in size: CGSize) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            FocusQueueListView(
                queue: queue,
                activeTask: activeTask,
                activeSegmentID: activeSegment?.id
            )
            .frame(height: Self.macQueueHeight(for: size.height))
            .flowGlass(radius: FlowRadius.large)
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.l)
        }
        .frame(height: size.height)
        .allowsHitTesting(true)
        #else
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            FocusNowBar(
                queue: queue,
                activeTask: activeTask,
                activeSegmentID: activeSegment?.id
            ) {
                queueSheetShown = true
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.l)
        }
        .frame(height: size.height)
        .allowsHitTesting(true)
        #endif
    }

    #if os(macOS)
    /// Ported forward from the deleted `FocusCardDetent.height(for:)`'s own
    /// `.open` formula, so the wheel's reserved space (see `wheelLayer`)
    /// still matches what is actually drawn beneath it. macOS has no bar to
    /// measure — spec is silent on its sizing beyond "render inline where
    /// the card sits today" — so the existing pattern in this file is
    /// carried forward rather than invented fresh.
    private static func macQueueHeight(for totalHeight: CGFloat) -> CGFloat {
        max(180, totalHeight * 0.20)
    }
    #endif

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
        return "\(countdownMinutesText) min"
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

    /// Which of the two truthful empty screens an idle Focus shows. The old
    /// single "That's the plan done" claimed completion even while captured
    /// tasks sat unplanned in the Inbox — the founder captured a task and
    /// could not see how it reached the wheel (Task 61). Pure so the
    /// boundary is covered without a store.
    enum EmptyStateKind: Equatable {
        case planPrompt(inboxCount: Int)
        case dayDone
    }

    static func emptyState(inboxCount: Int) -> EmptyStateKind {
        inboxCount > 0 ? .planPrompt(inboxCount: inboxCount) : .dayDone
    }

    /// The app does the counting — cognitive profile: state restated on
    /// screen, arithmetic never left to the reader.
    static func planPromptMessage(inboxCount: Int) -> String {
        inboxCount == 1
            ? "1 task in your Inbox is waiting to be planned."
            : "\(inboxCount) tasks in your Inbox are waiting to be planned."
    }

    private var inboxCount: Int { SmartView.inbox.matches(allTasks).count }

    @ViewBuilder
    private var emptyLayer: some View {
        switch Self.emptyState(inboxCount: inboxCount) {
        case .planPrompt(let count): planPrompt(count)
        case .dayDone: completionState
        }
    }

    /// Signposting only — wheel-philosophy: the wheel takes no walk-ins, so
    /// this routes to Plan rather than offering tasks to pick from here.
    private func planPrompt(_ count: Int) -> some View {
        VStack(spacing: FlowSpacing.l) {
            FlowEmptyState(
                symbol: "tray",
                title: "Nothing on the wheel yet",
                message: Self.planPromptMessage(inboxCount: count)
            )
            PrimaryActionButton("Plan your day", systemImage: "square.stack") {
                NotificationCenter.default.post(
                    name: .flowmapOpenDeepLink,
                    object: DeepLinkRequest(destination: .inbox)
                )
            }
            .frame(maxWidth: 320)
            SecondaryActionButton("Start a focus session", systemImage: "timer") {
                showingDurationPicker = true
            }
        }
        .padding(FlowSpacing.screen)
    }

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
        announce(new.announcement)
    }

    /// Persist where the close-up settled, so the wheel is where it was left
    /// next session — the same promise the settled level already makes.
    private func setMagnify(_ factor: Double) {
        guard let flow else { return }
        let clamped = FocusWheelGeometry.clampMagnify(factor)
        guard flow.settings.wheelMagnifyFactor != clamped else { return }
        flow.settings.wheelMagnifyFactor = clamped
        try? context.save()
        announce(magnifyAnnouncement(for: clamped))
    }

    /// One doubling in either direction, for the VoiceOver adjustable action.
    private func stepMagnify(_ delta: Int) {
        setMagnify(FocusWheelGeometry.steppedMagnifyFactor(from: magnification, delta: delta))
    }

    private var magnifyAnnouncement: String { magnifyAnnouncement(for: magnification) }

    private func magnifyAnnouncement(for factor: Double) -> String {
        let rounded = Int(factor.rounded())
        return rounded <= 1 ? "Whole wheel" : "Magnified \(rounded) times"
    }

    /// The one brief readout both zoom styles use, so a settle is confirmed the
    /// same way whichever the pinch is driving.
    private func announce(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { visibilityHUD = text }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeIn(duration: 0.25)) { visibilityHUD = nil }
        }
    }

    /// One settled level in either direction, for the VoiceOver adjustable
    /// action. It walks `carouselModes` so the rotor and the pinch can never
    /// disagree about which levels exist, and it routes through `setVisibility`
    /// so the announcement and the persistence are the ones already in use.
    private func stepVisibility(_ delta: Int) {
        let modes = WheelVisibility.carouselModes
        guard let index = modes.firstIndex(of: visibility) else { return }
        let next = min(modes.count - 1, max(0, index + delta))
        setVisibility(modes[next])
    }

    #if !os(macOS)
    /// Pinching zooms the ring live: it grows and shrinks under the fingers,
    /// through the layouts between the four views, and settles on the nearest
    /// one when they lift. It magnifies like a map: spreading the fingers
    /// enlarges one task until it fills the ring, pinching inward pulls back to
    /// the whole day. The mapping and the settle both live in `FocusWheelGeometry`,
    /// so the gesture and the settled level can never drift apart. Since the
    /// founder's ruling removed the chips row, the non-gesture path the HIG asks
    /// for is the wheel's `.accessibilityAdjustableAction`, not a visible
    /// control.
    ///
    /// Nothing is persisted and no HUD fires until release: a per-frame write
    /// would announce three modes on the way to the one that was wanted.
    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                // The close-up magnifies the drawing instead of re-forming it:
                // one layout, drawn bigger about the pointer, so spreading the
                // fingers pushes the far side of the ring off the screen.
                if zoomStyle == .magnify {
                    if liveMagnify == nil {
                        pinchBaseMagnify = magnification
                    }
                    liveMagnify = FocusWheelGeometry.magnifyFactor(
                        base: pinchBaseMagnify,
                        magnification: value.magnification
                    )
                    return
                }
                if liveZoom == nil {
                    pinchBaseZoom = FocusWheelGeometry.carouselZoom(for: visibility)
                }
                liveZoom = FocusWheelGeometry.carouselZoom(
                    base: pinchBaseZoom,
                    magnification: value.magnification
                )
                // Set outside any animation: the swell is the dial answering
                // the fingers, and easing it would put it behind the hand.
                dialScale = FocusWheelGeometry.reformScale(magnification: value.magnification)
            }
            .onEnded { value in
                if zoomStyle == .magnify {
                    let settled = FocusWheelGeometry.magnifyFactor(
                        base: pinchBaseMagnify,
                        magnification: value.magnification
                    )
                    liveMagnify = nil
                    setMagnify(settled)
                    return
                }
                let settled = FocusWheelGeometry.settledCarouselMode(
                    forZoom: FocusWheelGeometry.carouselZoom(
                        base: pinchBaseZoom,
                        magnification: value.magnification
                    )
                )
                liveZoom = nil
                // The level settles and the swell lets go together, with the
                // same gentleness the time-travel drag springs back at.
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.4, dampingFraction: 0.86)
                ) {
                    dialScale = 1
                }
                setVisibility(settled)
            }
    }

    /// Drag the band to look ahead. The ring turns with the finger and springs
    /// back on release: nothing is committed, so a peek at what is coming can
    /// never be mistaken for a change to the plan.
    ///
    /// It lives on the dial, far from every screen edge, so it cannot fight the
    /// back swipe, the tab bar or the home indicator (HIG: never compete with a
    /// system gesture). The clamp and the degree mapping are both
    /// `FocusWheelGeometry`'s, so the travel limit matches the queue that is
    /// actually drawn.
    private var timeTravelGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Two fingers mean zoom, not travel: a pinch that lands a
                // fraction unevenly must never spin the ring as well.
                guard liveZoom == nil, liveMagnify == nil else { return }
                if !isDragging {
                    isDragging = true
                    dragBaseOffset = previewOffset
                }
                previewOffset = FocusWheelGeometry.clampDragPreview(
                    dragBaseOffset + FocusWheelGeometry.dragPreviewOffset(
                        translationWidth: value.translation.width,
                        // Against the ring as DRAWN: under the close-up the
                        // band is magnified, so the same finger travel should
                        // cover proportionally fewer degrees of it.
                        radius: FocusWheelGeometry.magnifiedRadius(dialRadius, factor: magnification)
                    ),
                    zoom: zoom,
                    durations: wheelItems.map(\.minutes),
                    elapsed: progress
                )
            }
            .onEnded { _ in
                isDragging = false
                // Gentle by default; Reduce Motion gets a short easeOut with no
                // overshoot, since a spring's bounce is exactly what it asks to
                // be spared.
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.45, dampingFraction: 0.85)
                ) {
                    previewOffset = 0
                }
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

/// Duration chooser for a focus session with no task attached. Deliberately
/// offers no task list: tasks enter the wheel from Plan only, never picked
/// from here (state/specs/wheel-philosophy.md — the wheel takes no walk-ins).
struct FocusDurationPicker: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 30 minutes is the free-focus default; 15 remains a preset.
    private let presets = [15, 25, 30, 45, 60]

    @State private var minutes: Int = 30

    let onStart: (Int) -> Void

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

            PrimaryActionButton("Start focus", systemImage: "play.fill") {
                onStart(minutes)
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
}
