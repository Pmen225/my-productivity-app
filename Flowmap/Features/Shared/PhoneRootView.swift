#if !os(macOS)
import SwiftData
import SwiftUI
import UIKit

/// The iPhone shell: a real, native tab bar with three destinations —
/// Plan, Focus, Settings — restyled with `FlowTheme`.
///
/// Decision 1b (2026-07-29) reverses the `≡` glass menu subtask 37 built.
/// That menu still switched tabs through a hidden 7-tag `TabView`, and iOS
/// collapses any `TabView` past 5 tags into a stock system "More" list
/// regardless of `.toolbar(.hidden, for: .tabBar)` — confirmed the hard way
/// on Stats/Settings. Capping this `TabView` at exactly 5 tags and letting it
/// draw its own chrome (instead of hiding it behind a custom overlay) avoids
/// the bug and gives a genuinely native tab bar, not a web-style hamburger.
///
/// Decision 40/41 (2026-08-10) drop this to three tags: Map and Calendar
/// left the bar. Map + Today folded into Plan as its own segment (the Map
/// tab is gone); Calendar is now a button on Plan's own nav bar instead of
/// a tab. Founder, verbatim and angry: "TODAY should [come] FROM MAPS, only
/// ONE TODAY... Map tab should be gone, content inside moved to plan tab."
struct PhoneRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allTasks: [FlowTask]

    // The mockup's launch screen is Focus (`00-initial.png`). The focused
    // hierarchy harness opens Plan directly so screenshot evidence does not
    // depend on iOS 26 tab-hit-test timing; production still always opens Focus.
    @State private var tab: DeepLink = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-flowmapOpenAISettings") { return .settings }
        if arguments.contains("-flowmapHarnessHierarchy")
            || arguments.contains("-flowmapOpenAIHarness")
            || arguments.contains("-flowmapOpenAIToday")
            || arguments.contains("-flowmapOpenAIMap") {
            return .library
        }
        return .focus
    }()
    @State private var showingAssistant = false
    @State private var showingCapture = false
    @State private var showingLibraryPanel = false
    @State private var selectedSettingsRow: SettingsHubRow?
    @GestureState private var drawerDragTranslation: CGFloat = 0
    @State private var planSegment: LibraryView.PlanSegment = {
        if ProcessInfo.processInfo.arguments.contains("-flowmapOpenAIMap") { return .map }
        return .today
    }()
    // Today is no longer a tab (decision 1b) — it stays reachable by deep
    // link and notification, presented as a sheet, until T3 folds it into
    // the Map page as a pane.
    @State private var showingToday = false
    // Stats also isn't a tab — it's a chart-icon push on Plan's own
    // NavigationStack. Owned here so the deep-link handler can drive it from
    // outside Plan/LibraryView.
    @State private var pushStats = false

    private var inboxCount: Int {
        SmartView.inbox.matches(allTasks).count
    }

    var body: some View {
        GeometryReader { proxy in
            let revealWidth = FlowOpenAISidebarMetrics.revealWidth(for: proxy.size.width)
            let foregroundOffset = drawerForegroundOffset(revealWidth: revealWidth)
            let revealProgress = revealWidth > 0 ? foregroundOffset / revealWidth : 0

            ZStack(alignment: .topLeading) {
                FlowOpenAILibraryPanel(
                    width: revealWidth,
                    selectedDestination: selectedDrawerDestination,
                    onSelectPlan: selectLibrarySegment,
                    onSelectSettings: selectSettings,
                    onSelectStats: selectStats
                )
                .frame(
                    width: revealWidth,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
                .accessibilityIdentifier("flowmap-drawer")
                .allowsHitTesting(showingLibraryPanel)
                .accessibilityHidden(!showingLibraryPanel)

                ZStack(alignment: .topLeading) {
                    foregroundSurface
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .accessibilityIdentifier("flowmap-foreground")
                        .accessibilitySortPriority(showingLibraryPanel ? -1 : 0)
                        .allowsHitTesting(!showingLibraryPanel)
                        .accessibilityHidden(showingLibraryPanel)

                    if showingLibraryPanel {
                        chromeCircleButton(
                            systemImage: "line.3.horizontal.decrease",
                            label: "Close library",
                            badge: inboxCount,
                            action: closeLibraryPanel
                        )
                        .position(
                            x: (proxy.size.width - revealWidth) / 2,
                            y: proxy.safeAreaInsets.top + FlowSpacing.s + FlowControlSize.minimumTouch / 2
                        )
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
                .contentShape(Rectangle())
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: FlowOpenAISidebarMetrics.foregroundRadius * revealProgress,
                        bottomLeadingRadius: FlowOpenAISidebarMetrics.foregroundRadius * revealProgress
                    )
                )
                .shadow(
                    color: FlowTheme.shadow(scheme).opacity(revealProgress),
                    radius: 36 * revealProgress,
                    x: -14 * revealProgress
                )
                .offset(x: foregroundOffset)
                .animation(reduceMotion ? nil : FlowMotion.drawerReveal, value: showingLibraryPanel)
                .simultaneousGesture(
                    drawerSwipeGesture(revealWidth: revealWidth),
                    including: showingLibraryPanel ? .all : .none
                )

                if !showingLibraryPanel {
                    Color.clear
                        .frame(width: FlowSpacing.l)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(drawerSwipeGesture(revealWidth: revealWidth))
                        .accessibilityHidden(true)
                }

            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(showingLibraryPanel ? .isModal : [])
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay { FlowMomentOverlay() }
        .sheet(isPresented: $showingAssistant) {
            NavigationStack { AssistantScreen() }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView()
                // Task composition needs the full canvas: the medium detent
                // opened behind the keyboard and cropped the worth control on
                // first contact. Keep the native sheet and its dismissal cue,
                // but start at the compose-sized detent used by Mail/Messages.
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(FlowRadius.large)
        }
        // Today: sheet, not full-screen cover — matches the ambient idiom
        // this shell already uses for Assistant/Search/Quick capture, and it
        // is an interim, deep-link-only destination until T3 folds it into
        // Map + Today.
        .sheet(isPresented: $showingToday) {
            NavigationStack { TodayView() }
        }
        .sheet(item: rolloverReviewBinding) { _ in
            RolloverReviewView()
        }
        // Decision 40/41: `.map`/`.calendar` are no longer tabs on iPhone, but
        // nothing in the app posts those destinations as a deep link today
        // (grepped every `DeepLinkRequest(destination:` call site), so the
        // `default` branch below staying a no-op-on-phone is dead code, not a
        // live gap. `.today` keeps its existing sheet path rather than
        // threading a `PlanSegment` binding down through `LibraryView` —
        // both render the identical `TodayView`, so behaviour is preserved.
        .onReceive(NotificationCenter.default.publisher(for: .flowmapOpenDeepLink)) { notification in
            guard let request = notification.object as? DeepLinkRequest else { return }
            switch request.destination {
            case .assistant: showingAssistant = true
            case .inbox, .library:
                tab = .library
                planSegment = .inbox
            case .today:
                tab = .library
                planSegment = .today
            case .map:
                tab = .library
                planSegment = .map
            case .calendar:
                tab = .library
                planSegment = .today
            case .stats:
                tab = .library
                pushStats = true
            case .focus: tab = .focus
            case .settings:
                selectedSettingsRow = nil
                tab = .settings
            }
        }
    }

    private var foregroundSurface: some View {
        ZStack {
            // The drawer is a stationary underlay. Its rows must never show
            // through the closed foreground's padded chrome region.
            FlowTheme.background(scheme).ignoresSafeArea()
            selectedContent
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep the app's own chrome inside the moving foreground. The
            // system status bar remains outside this surface and therefore
            // stays fixed while the drawer reveals beneath it.
            .safeAreaInset(edge: .top, spacing: 0) { openAITopChrome }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if tab == .library, !pushStats { positionedCaptureAssistantOrb }
            }
            // `safeAreaInset` adds its chrome outside the content's original
            // background. Paint the completed surface last so the stationary
            // drawer cannot bleed through any closed-state inset.
            .background(FlowTheme.background(scheme).ignoresSafeArea())
            .animation(reduceMotion ? nil : FlowMotion.selection, value: tab)
    }

    @ViewBuilder
    private var selectedContent: some View {
        if tab == .focus {
            NavigationStack { FocusScreen() }
                .toolbar(.hidden, for: .navigationBar)
                .transition(.opacity)
        } else if tab == .settings {
            NavigationStack {
                SettingsScreen(selectedRow: $selectedSettingsRow, showsTitle: false)
            }
                .toolbar(.hidden, for: .navigationBar)
                .transition(.opacity)
        } else {
            NavigationStack {
                LibraryView(
                    planSegment: $planSegment,
                    pushStats: $pushStats,
                    onSearchResult: navigate(to:)
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var openAITopChrome: some View {
        if pushStats {
            destinationTopChrome(
                title: "Stats",
                leadingSystemImage: "chevron.left",
                leadingLabel: "Back to Plan"
            ) {
                pushStats = false
            }
        } else if tab == .settings {
            if let selectedSettingsRow {
                destinationTopChrome(
                    title: selectedSettingsRow.title,
                    leadingSystemImage: "chevron.left",
                    leadingLabel: "Back to Settings"
                ) {
                    self.selectedSettingsRow = nil
                }
            } else {
                destinationTopChrome(
                    title: "Settings",
                    leadingSystemImage: "line.3.horizontal.decrease",
                    leadingLabel: "Open library",
                    badge: inboxCount
                ) {
                    withAnimation(reduceMotion ? FlowMotion.fade : FlowMotion.drawerReveal) {
                        showingLibraryPanel.toggle()
                    }
                }
            }
        } else {
            primaryTopChrome
        }
    }

    private var primaryTopChrome: some View {
        HStack(spacing: FlowSpacing.m) {
            chromeCircleButton(
                systemImage: "line.3.horizontal.decrease",
                label: "Open library",
                badge: inboxCount
            ) {
                withAnimation(reduceMotion ? FlowMotion.fade : FlowMotion.drawerReveal) {
                    showingLibraryPanel.toggle()
                }
            }
            .opacity(showingLibraryPanel ? 0 : 1)

            Spacer(minLength: 0)

            HStack(spacing: FlowSpacing.xxs) {
                modeButton("Today", selected: tab == .library && planSegment == .today) {
                    tab = .library
                    planSegment = .today
                }
                modeButton("Focus", selected: tab == .focus) {
                    tab = .focus
                }
            }
            .padding(FlowSpacing.xxs)
            .background(Capsule().fill(FlowTheme.surfaceSunken(scheme)))
            .overlay(Capsule().stroke(FlowTheme.separator(scheme), lineWidth: 1))

            Spacer(minLength: 0)

            chromeCircleButton(systemImage: "sparkles", label: "Open assistant") {
                showingAssistant = true
            }
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.s)
        .background(FlowTheme.background(scheme).opacity(0.96))
    }

    private func destinationTopChrome(
        title: String,
        leadingSystemImage: String,
        leadingLabel: String,
        badge: Int = 0,
        leadingAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: FlowSpacing.m) {
            chromeCircleButton(
                systemImage: leadingSystemImage,
                label: leadingLabel,
                badge: badge,
                action: leadingAction
            )

            Spacer(minLength: 0)

            Text(title)
                .font(FlowFont.screenTitleCompact)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityIdentifier("flowmap-destination-title")

            Spacer(minLength: 0)

            chromeCircleButton(systemImage: "sparkles", label: "Open assistant") {
                showingAssistant = true
            }
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.s)
        .background(FlowTheme.background(scheme).opacity(0.96))
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FlowFont.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: 64, height: 34)
                .background(Capsule().fill(selected ? FlowTheme.surface(scheme) : .clear))
                .overlay {
                    if selected {
                        Capsule().stroke(FlowTheme.separator(scheme), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(FlowOpenAIPressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chromeCircleButton(
        systemImage: String,
        label: String,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                .background(Circle().fill(FlowTheme.background(scheme)))
                .overlay(Circle().stroke(FlowTheme.separator(scheme), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(FlowFont.durationChip)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(FlowTheme.info))
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(FlowOpenAIPressStyle())
        .flowHitTarget()
        .accessibilityLabel(label)
    }

    private func selectLibrarySegment(_ segment: LibraryView.PlanSegment) {
        planSegment = segment
        tab = .library
        withAnimation(reduceMotion ? FlowMotion.fade : FlowMotion.drawerReveal) {
            showingLibraryPanel = false
        }
    }

    private var selectedDrawerDestination: FlowOpenAILibraryPanel.Destination? {
        if tab == .settings { return .settings }
        guard tab == .library else { return nil }
        switch planSegment {
        case .today: return nil
        case .inbox: return .inbox
        case .map: return .map
        }
    }

    private func selectSettings() {
        selectedSettingsRow = nil
        tab = .settings
        closeLibraryPanel()
    }

    private func selectStats() {
        tab = .library
        pushStats = true
        closeLibraryPanel()
    }

    private func closeLibraryPanel() {
        withAnimation(reduceMotion ? FlowMotion.fade : FlowMotion.drawerReveal) {
            showingLibraryPanel = false
        }
    }

    private func drawerForegroundOffset(revealWidth: CGFloat) -> CGFloat {
        let restingOffset = showingLibraryPanel ? revealWidth : 0
        guard !reduceMotion else { return restingOffset }
        return min(max(restingOffset + drawerDragTranslation, 0), revealWidth)
    }

    private func drawerSwipeGesture(revealWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($drawerDragTranslation) { value, translation, _ in
                guard !reduceMotion else { return }
                let horizontal = abs(value.translation.width)
                guard horizontal > abs(value.translation.height) else { return }
                guard showingLibraryPanel
                        || (value.startLocation.x <= FlowSpacing.l && value.translation.width > 0)
                else { return }
                translation = value.translation.width
            }
            .onEnded { handleDrawerSwipe($0, revealWidth: revealWidth) }
    }

    private func handleDrawerSwipe(_ value: DragGesture.Value, revealWidth: CGFloat) {
        let horizontal = abs(value.translation.width)
        guard horizontal > abs(value.translation.height) else { return }

        guard showingLibraryPanel
                || (value.startLocation.x <= FlowSpacing.l && value.translation.width > 0)
        else { return }

        let restingOffset = showingLibraryPanel ? revealWidth : 0
        let releaseTranslation = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
            ? value.predictedEndTranslation.width
            : value.translation.width
        let projectedOffset = min(
            max(restingOffset + releaseTranslation, 0),
            revealWidth
        )
        withAnimation(reduceMotion ? nil : FlowMotion.drawerReveal) {
            showingLibraryPanel = projectedOffset >= revealWidth / 2
        }
    }

    /// The shell's single capture control. Assistant belongs to top chrome.
    private var captureAssistantOrb: some View {
        FlowFloatingButton(
            systemImage: "plus",
            diameter: FlowControlSize.create,
            background: FlowTheme.accentFill,
            foreground: .white,
            shadowColor: FlowTheme.accentShadow,
            shellStroke: FlowTheme.separator(scheme),
            // Tiimo's branded face is approximately 70% of the detached
            // circle. Keep the outer shell equal to the tab pill while the
            // accent face stays inside it as a distinct Liquid Glass plate.
            faceScale: 0.70,
            iconScale: 0.32,
            accessibilityLabel: "New task, project or initiative",
            hapticsEnabled: flow?.settings.focusHapticsEnabled ?? false
        ) {
            showingCapture = true
        }
    }

    @ViewBuilder
    private var positionedCaptureAssistantOrb: some View {
        captureAssistantOrb
            .padding(.trailing, FlowSpacing.xl)
            .padding(.bottom, FlowSpacing.m)
    }

    private func navigate(to result: SearchResult) {
        switch result.kind {
        case .task, .project, .note: tab = .library
        case .assistantThread: showingAssistant = true
        }
    }

    private var rolloverReviewBinding: Binding<RolloverReview?> {
        Binding(
            get: { flow?.pendingRolloverReview },
            set: { value in
                if value == nil { flow?.pendingRolloverReview = nil }
            }
        )
    }
}

private struct FlowOpenAIPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
    }
}

private enum FlowOpenAISidebarMetrics {
    /// OpenAI Apps iOS Navigation source, node 6:64324: 325pt drawer on a
    /// 402pt iPhone. Compact screens retain one native 44pt close strip.
    static let sourceWidth: CGFloat = 325
    static let minimumForegroundStrip: CGFloat = 44
    static let contentInset: CGFloat = 14
    static let rowHeight: CGFloat = 44
    static let iconFrame: CGFloat = 25
    static let foregroundRadius: CGFloat = 30

    static func revealWidth(for availableWidth: CGFloat) -> CGFloat {
        min(sourceWidth, max(0, availableWidth - minimumForegroundStrip))
    }
}

private struct FlowOpenAILibraryPanel: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Destination: Hashable {
        case settings, inbox, map, stats
    }

    let width: CGFloat
    let selectedDestination: Destination?
    let onSelectPlan: (LibraryView.PlanSegment) -> Void
    let onSelectSettings: () -> Void
    let onSelectStats: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        navigationContent
                        footer
                    }
                }
                .safeAreaPadding(.top)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ScrollView { navigationContent }
                    footer
                }
            }
        }
        .foregroundStyle(FlowTheme.primaryText(scheme))
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
    }

    private var navigationContent: some View {
        VStack(spacing: 0) {
            destinationRow("Inbox", systemImage: "tray", selected: selectedDestination == .inbox) {
                onSelectPlan(.inbox)
            }
            destinationRow("Map", systemImage: "point.3.connected.trianglepath.dotted", selected: selectedDestination == .map) {
                onSelectPlan(.map)
            }
            destinationRow("Stats", systemImage: "chart.bar", selected: selectedDestination == .stats) {
                onSelectStats()
            }
        }
    }

    private var header: some View {
        Text("Flowmap")
            .font(FlowFont.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: FlowOpenAISidebarMetrics.rowHeight, alignment: .leading)
            .padding(.horizontal, FlowOpenAISidebarMetrics.contentInset)
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            footerRows
                .padding(.horizontal, FlowOpenAISidebarMetrics.contentInset)
        } else {
            footerRows
                .padding(.horizontal, FlowOpenAISidebarMetrics.contentInset)
                .frame(height: FlowOpenAISidebarMetrics.rowHeight + FlowSpacing.s)
        }
    }

    private var footerRows: some View {
        Button(action: onSelectSettings) {
            HStack(spacing: 15) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: FlowOpenAISidebarMetrics.iconFrame, height: FlowOpenAISidebarMetrics.iconFrame)
                Text("Settings")
                    .font(FlowFont.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: FlowSpacing.s)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: FlowOpenAISidebarMetrics.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FlowOpenAIPressStyle())
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("flowmap-footer-settings")
    }

    private func destinationRow(
        _ title: String,
        systemImage: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: FlowOpenAISidebarMetrics.iconFrame, height: FlowOpenAISidebarMetrics.iconFrame)
                Text(title)
                    .font(FlowFont.body.weight(.medium))
                Spacer(minLength: FlowSpacing.s)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: FlowOpenAISidebarMetrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.tile, style: .continuous)
                    .fill(selected ? FlowTheme.primaryText(scheme).opacity(accessibilityContrast == .increased ? 0.10 : 0.05) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FlowOpenAIPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("flowmap-destination-\(title.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .padding(.horizontal, FlowOpenAISidebarMetrics.contentInset)
    }

}

/// Applies a visual-only translation to SwiftUI's underlying native tab bar.
/// Keeping the adjustment on `UITabBar` preserves native tab selection,
/// badges, accessibility, Liquid Glass, and the content's full-width layout.
@available(iOS 26.0, *)
private struct NativeTabBarHorizontalShift: UIViewRepresentable {
    let distance: CGFloat

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(distance: distance)
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.distance = distance
        view.applyShift()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Void) {
        view.resetShift()
    }

    final class ProbeView: UIView {
        var distance: CGFloat

        init(distance: CGFloat) {
            self.distance = distance
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.applyShift()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyShift()
        }

        func applyShift() {
            guard let tabBar = resolvedTabBarController()?.tabBar else { return }
            tabBar.transform = .identity
            let shift = CGAffineTransform(
                translationX: -distance,
                y: 0
            )
            tabBar.subviews.forEach { $0.transform = shift }
        }

        func resetShift() {
            guard let tabBar = resolvedTabBarController()?.tabBar else { return }
            tabBar.transform = .identity
            tabBar.subviews.forEach { $0.transform = .identity }
        }

        private func resolvedTabBarController() -> UITabBarController? {
            guard let root = window?.rootViewController else { return nil }
            return findTabBarController(in: root)
        }

        private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }
            if let presented = controller.presentedViewController,
               let match = findTabBarController(in: presented) {
                return match
            }
            for child in controller.children {
                if let match = findTabBarController(in: child) {
                    return match
                }
            }
            return nil
        }
    }
}

/// Everything that does not earn its own tab.
struct LibraryView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query private var allTasks: [FlowTask]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \Initiative.sortOrder) private var initiatives: [Initiative]
    // Same sort `NotesListView` uses, so "note preview row order" cannot
    // drift between the two places notes are listed.
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    /// Stats dropped off the tab bar (decision 1b) and is reached instead by
    /// a chart-icon push on this screen's own `NavigationStack`. Owned by
    /// `PhoneRootView` so its deep-link handler can drive the push from
    /// outside Plan too.
    @Binding var pushStats: Bool
    /// Routes a chosen search result, so a Library search behaves like the
    /// shell's own — selecting a result must actually go somewhere.
    let onSearchResult: (SearchResult) -> Void

    @State private var showingSearch = false
    /// The Plan tab's fixed top-level page (decision 40). Replaces the old
    /// task-page chips and the "Smart task views" menu.
    @Binding var planSegment: PlanSegment
    @Namespace private var planSegmentSelection
    /// The task tapped inside an unfolded TASKS row. A sheet, not a push into
    /// Focus — decision 10 already answered this exact question for the
    /// Today pane, and one screen cannot mean two things by the same tap.
    /// Mirrors `TaskListScreen.swift`'s own `selectedTask` wiring.
    @State private var inspectedTask: FlowTask?
    /// The note tapped inside the unfolded Notes row — opens the same
    /// `NoteEditorView` a push from `NotesListView` would (ruling 7, T6
    /// stage 2), as a sheet to match `inspectedTask`'s presentation above.
    @State private var inspectedNote: Note?
    /// Hosted on this screen's top-level List, not inside the Notes accordion:
    /// a presentation modifier below a nested Section can silently fail to
    /// present. The contextual menu only selects the note to attach.
    @State private var attachmentPickerNote: Note?
    /// Which BUILD and REVIEW accordions are open, keyed by a stable id per row.
    @State private var expandedRows: Set<String> = []
    /// The prioritise duel and plan-preview sheets `PlanInboxSection`'s
    /// buttons trigger, hosted HERE rather than inside `PlanInboxSection`
    /// itself: `PlanInboxSection` is only one `Section` among several inside
    /// this screen's own `List`, and a `.sheet` attached that deep never
    /// presented — see the comment on `PlanInboxSection`'s bindings of the
    /// same names. Owning them at this List's own top level is the pattern
    /// `inspectedTask`/`inspectedNote`/`showingSearch` above already use
    /// successfully.
    @State private var showingDuel = false
    @State private var showingPlanPreview = false
    @State private var planProposal: PlanProposal?
    @State private var pendingProjectDelete: Project?
    /// Drives the project push explicitly. The accordion cannot use
    /// `NavigationLink(value:)`: its expanded rows all share ONE `List` cell,
    /// and every link in that cell activates together — one tap on any project
    /// pushed all five and stranded the user in the last one.
    @State private var selectedProject: Project?
    @State private var editingInitiative: Initiative?

    /// The Plan tab's three fixed top-level pages (decision 40, 2026-08-10).
    /// Replaces the old task-page chips and "Smart task views" menu, which
    /// the founder called "so tiny to touch... very claustrophobic". One
    /// Today (folds Map + Today's old Today pane into Plan), one Map, Inbox
    /// unchanged. No menu, no paging — all three always on screen at once.
    enum PlanSegment: String, CaseIterable, Identifiable {
        case today, inbox, map

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .inbox: "Inbox"
            case .map: "Map"
            }
        }
    }

    init(
        planSegment: Binding<PlanSegment>,
        pushStats: Binding<Bool>,
        onSearchResult: @escaping (SearchResult) -> Void
    ) {
        _planSegment = planSegment
        _pushStats = pushStats
        self.onSearchResult = onSearchResult
    }

    /// Ordered peers in the Plan tab's task surface. Inbox is deliberately
    /// page zero because it is the capture-to-triage entry point; completed is
    /// last because it is history, not the next action.
    ///
    /// Retained purely for `taskPageContent`/`smartTaskPages`/
    /// `taskPageSelection` below, which `Tests/LibraryAccordionTests.swift`
    /// covers directly and Slice 2's Browse rows reuse — the pager UI that
    /// used to switch over this enum is gone (decision 40).
    enum TaskPage: String, CaseIterable, Identifiable {
        case inbox, today, upcoming, anytime, allTasks, completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: "Inbox"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .anytime: "Anytime"
            case .allTasks: "All tasks"
            case .completed: "Completed"
            }
        }

        var smartView: SmartView? {
            switch self {
            case .inbox: nil
            case .today: .today
            case .upcoming: .upcoming
            case .anytime: .anytime
            case .allTasks: .allTasks
            case .completed: .completed
            }
        }
    }

    static let taskPages = TaskPage.allCases
    /// The five smart destinations intentionally share one menu. Inbox is
    /// the separate default capture button and is not a peer in this menu.
    static let smartTaskPages: [TaskPage] = [.today, .upcoming, .anytime, .allTasks, .completed]
    static let initialTaskPage: TaskPage = .inbox

    /// Kept pure so the selected-page rule is covered without needing a
    /// simulator to drive a swipe. Choosing the current page is intentionally
    /// idempotent; it should not restart a transition or collapse Inbox edits.
    static func taskPageSelection(from current: TaskPage, choosing candidate: TaskPage) -> TaskPage {
        current == candidate ? current : candidate
    }

    /// The exact tasks a non-Inbox page shows, sorted for display. Both the
    /// page and this helper read the same SmartView filter, so they cannot
    /// drift into different counts or contents.
    static func taskPageContent(for view: SmartView, in tasks: [FlowTask], now: Date) -> [FlowTask] {
        view.sorted(view.matches(tasks, now: now), grouping: .manual)
    }

    var body: some View {
        planSurface
        .background(FlowTheme.background(scheme).ignoresSafeArea())
            .navigationDestination(isPresented: $pushStats) {
                ProgressScreen(showsTitle: false)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .sheet(isPresented: $showingSearch) {
                GlobalSearchView { result in onSearchResult(result) }
            }
            .sheet(item: $inspectedTask) { task in
                NavigationStack { TaskDetailInspector(task: task) }
            }
            .sheet(item: $inspectedNote) { note in
                NavigationStack { NoteEditorView(note: note) }
            }
            .sheet(item: $attachmentPickerNote) { note in
                NoteAttachPickerView(
                    candidates: NoteAttachCandidates.display(noteCandidates, attached: note.task),
                    current: note.task
                ) { task in
                    toggleAttach(note: note, task: task)
                }
            }
            // Hosted here, not on `PlanInboxSection`'s `Section`. A `.sheet`
            // attached to a `Section` nested inside this `List` never presents.
            .fullScreenCover(isPresented: $showingDuel) {
                PrioritiseDuelView(tasks: SmartView.today.matches(allTasks, now: flow?.now ?? Date()))
            }
            .sheet(isPresented: $showingPlanPreview) {
                PlanPreviewView(
                    proposal: planProposal ?? PlanProposal(),
                    tasksByID: Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) }),
                    onApply: applyPlan,
                    onReplanWholeDay: replanWholeDay
                )
            }
            .flowDeleteConfirmation(
                isPresented: projectDeleteBinding,
                itemTitle: pendingProjectDelete?.title ?? "",
                hasChildren: !(pendingProjectDelete?.tasks ?? []).isEmpty,
                onDelete: deletePendingProject
            )
            .sheet(item: $editingInitiative) { InitiativeEditSheet(initiative: $0) }
    }

    /// One fixed 3-way control replaces the old task-page chips and the
    /// "Smart task views" menu (decision 40). One implementation serves every
    /// supported iOS version: native Button interaction stays stable while the
    /// extracted OpenAI Apps control language supplies compact labels and a
    /// selected underline.
    @ViewBuilder
    private var planSegmentControl: some View {
        tokenPlanSegmentControl
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.top, FlowSpacing.s)
        .padding(.bottom, FlowSpacing.xs)
        .sensoryFeedback(.selection, trigger: planSegment)
    }

    private var tokenPlanSegmentControl: some View {
        HStack(spacing: FlowSpacing.xxs) {
            ForEach(PlanSegment.allCases) { segment in
                let isSelected = planSegment == segment

                Button {
                    selectPlanSegment(segment)
                } label: {
                    VStack(spacing: 0) {
                        Text(segment.title)
                            .font(FlowFont.caption.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(
                                isSelected
                                    ? FlowTheme.accentText(scheme)
                                    : FlowTheme.secondaryText(scheme)
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 40)

                        Rectangle()
                            .fill(isSelected ? FlowTheme.accent : .clear)
                            .frame(height: FlowSpacing.xs)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanSegmentPressStyle())
                .accessibilityIdentifier("plan-segment-\(segment.rawValue)")
                .accessibilityLabel(segment.title)
                .accessibilityHint("Shows the \(segment.title.lowercased()) view")
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, FlowSpacing.s)
        .background(
            Capsule(style: .continuous)
                .fill(FlowTheme.glass(scheme))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(FlowTheme.glassBorder(scheme), lineWidth: 1)
                }
        )
        .frame(minHeight: 52)
    }

    private func selectPlanSegment(_ segment: PlanSegment) {
        guard planSegment != segment else { return }
        if reduceMotion {
            planSegment = segment
        } else {
            withAnimation(FlowMotion.tap) {
                planSegment = segment
            }
        }
    }

    private struct PlanSegmentPressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
        }
    }

    /// Only the active segment is ever in the hierarchy — a `ZStack` with
    /// `if`/`else`, not `Group { switch }`, which has silently broken tab
    /// switching elsewhere in this app when paired with a `.toolbar`.
    @ViewBuilder
    private var planSurface: some View {
        ZStack {
            if planSegment == .today {
                TodayView()
            } else if planSegment == .inbox {
                openAIPlanInbox
            } else {
                AutoMapScreen(scope: .day, showsScreenTitle: false, includesBacklog: true)
            }
        }
        // A `List` claims the height on its own; the map's empty state does
        // not, and without this the whole `VStack` shrank to its content and
        // centred — dragging the segment control down off the header line.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var openAIPlanInbox: some View {
        let now = flow?.now ?? Date()
        let inbox = SmartView.inbox.matches(allTasks, now: now)
        let today = SmartView.today.matches(allTasks, now: now)
        let upNext = today.first

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(today.isEmpty ? "Plan one clear next action" : "\(today.count) clear next action\(today.count == 1 ? "" : "s")")
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .padding(.top, FlowSpacing.xl)

                Text("A calm view of what matters now.")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .padding(.top, FlowSpacing.s)

                if let upNext {
                    openAISectionLabel("Up next")
                        .padding(.top, FlowSpacing.xxxl)
                    openAITaskRow(upNext, time: nextTimeLabel(for: upNext), showsDivider: false)
                }

                HStack {
                    Text("Inbox")
                        .font(FlowFont.sectionTitle)
                    Spacer()
                    Text("\(inbox.count) task\(inbox.count == 1 ? "" : "s")")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                .padding(.top, FlowSpacing.xxxl)

                if inbox.isEmpty {
                    Text("Nothing waiting. Add a task below when something lands.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .padding(.vertical, FlowSpacing.xl)
                } else {
                    ForEach(Array(inbox.prefix(4).enumerated()), id: \.element.id) { index, task in
                        openAITaskRow(task, showsDivider: index < min(inbox.count, 4) - 1)
                    }
                }

                Button {
                    if today.count >= 2 {
                        showingDuel = true
                    } else {
                        planProposal = flow?.planToday(replanExisting: false)
                        showingPlanPreview = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                        Text("Plan today")
                            .font(FlowFont.cardTitle)
                            .foregroundStyle(FlowTheme.info)
                        Text("Flowmap can arrange these around your calendar.")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FlowOpenAIPressStyle())
                .padding(.top, FlowSpacing.xl)
                .accessibilityLabel("Plan today")
                .accessibilityHint("Prioritises today's tasks, then arranges them around your calendar")

                if !projects.isEmpty {
                    openAISectionLabel("Projects")
                        .padding(.top, FlowSpacing.xxxl)
                    ForEach(projects.prefix(3)) { project in
                        Button { selectedProject = project } label: {
                            HStack(spacing: FlowSpacing.m) {
                                Image(systemName: "folder")
                                    .foregroundStyle(FlowTheme.primaryText(scheme))
                                    .frame(width: FlowSpacing.xl)
                                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                                    Text(project.title).font(FlowFont.cardTitle)
                                    Text("\((project.tasks ?? []).count) task\((project.tasks ?? []).count == 1 ? "" : "s")")
                                        .font(FlowFont.caption)
                                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(FlowFont.caption.weight(.semibold))
                                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                            }
                            .frame(minHeight: FlowControlSize.create)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FlowOpenAIPressStyle())
                        Divider().overlay(FlowTheme.separator(scheme))
                    }
                }
            }
            .padding(.horizontal, FlowSpacing.xl)
            .padding(.bottom, FlowSpacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private func openAISectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(FlowFont.eyebrow)
            .foregroundStyle(FlowTheme.secondaryText(scheme))
            .tracking(0.6)
    }

    private func openAITaskRow(
        _ task: FlowTask,
        time: String? = nil,
        showsDivider: Bool = true
    ) -> some View {
        Button { inspectedTask = task } label: {
            HStack(alignment: .top, spacing: FlowSpacing.m) {
                if let time {
                    Text(time)
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .frame(width: FlowSpacing.xxxl, alignment: .leading)
                }

                Circle()
                    .fill(task.colour.base)
                    .frame(width: FlowSpacing.s, height: FlowSpacing.s)
                    .padding(.top, FlowSpacing.xs)

                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    Text(task.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(2)
                    Text(taskMetadata(task))
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(1)
                    if showsDivider {
                        Divider()
                            .overlay(FlowTheme.separator(scheme))
                            .padding(.top, FlowSpacing.s)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, FlowSpacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(FlowOpenAIPressStyle())
        .accessibilityLabel("\(task.title), \(taskMetadata(task))")
        .accessibilityHint("Opens task details")
    }

    private func nextTimeLabel(for task: FlowTask) -> String {
        guard let start = task.liveSegments
            .filter({ $0.state.occupiesTimeline })
            .sorted(by: { $0.startDate < $1.startDate })
            .first?.startDate else { return "Next" }
        return DurationFormatter.time(start)
    }

    private func taskMetadata(_ task: FlowTask) -> String {
        let duration = DurationFormatter.spoken(minutes: task.estimatedMinutes)
        guard let project = task.project else { return duration }
        return "\(project.title) · \(duration)"
    }

    private func planList(for page: TaskPage) -> some View {
        List {
            directListRoute

            taskPageSection(page)

            Section(header: sectionHeader("BUILD")) {
                projectsAccordion
                initiativesAccordion
                notesAccordion
            }
            .listRowBackground(FlowTheme.surface(scheme))

            browseSection
        }
        // Closes the dead vertical gaps between Personal, Inbox, and BUILD
        // (fix 2, board task 138) — the default `List` section spacing on
        // grouped style read as blank cream between cards. `.compact` is the
        // built-in preset for exactly this, not a new spacing constant.
        .listSectionSpacing(.compact)
        // This must live on the actual List. Applying an inset to the
        // surrounding NavigationStack is accepted but reserves no List space.
        // Safe-area padding shrinks the visible viewport, so a trailing count
        // can never sit behind the fixed capture control even mid-scroll.
        .safeAreaPadding(.bottom, FlowSpacing.floatingControlsInset)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Inbox plan preview

    /// Moved here from `PlanInboxSection` along with the sheet it drives —
    /// see the comment on that view's `showingPlanPreview` binding.
    private func applyPlan() {
        guard let flow, let planProposal else { return }
        flow.applyPlan(planProposal, replanExisting: false)
        showingPlanPreview = false
    }

    private func replanWholeDay() {
        guard let flow else { return }
        planProposal = flow.planToday(replanExisting: true)
    }

    // MARK: - TASKS pages

    /// Keep one direct list route for existing workflows (decision 40's
    /// "Lists strip", unchanged on the Inbox segment). Hosting this as a native
    /// List row (rather than a clipped title-strip link) preserves its 44pt
    /// hit target and existing navigation/options flow.
    @ViewBuilder
    private var directListRoute: some View {
        if let firstList = lists.first {
            Section {
                NavigationLink {
                    TaskListScreen(source: .userList(firstList))
                } label: {
                    libraryLabel(firstList.name, symbol: firstList.iconName, token: firstList.colour)
                }
                .accessibilityLabel(firstList.name)
                .accessibilityHint("Opens this list")
                .buttonStyle(FlowNavigationRowPressStyle())
            }
            .listRowBackground(FlowTheme.surface(scheme))
        }
    }

    @ViewBuilder
    private func taskPageSection(_ page: TaskPage) -> some View {
        if page == .inbox {
            PlanInboxSection(
                showingDuel: $showingDuel,
                showingPlanPreview: $showingPlanPreview,
                planProposal: $planProposal,
                showsHeader: false
            )
        } else if let view = page.smartView {
            let tasks = Self.taskPageContent(for: view, in: allTasks, now: flow?.now ?? Date())
            Section {
                if tasks.isEmpty {
                    emptyRow(view.emptyMessage)
                } else {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { inspectedTask = task }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))
        }
    }

    // MARK: - Browse (decision 40, Slice 2)

    /// Replaces the dead "Smart task views" menu: one large row per smart
    /// view, always visible, no menu to open first. Today is excluded — it
    /// is its own Plan segment now, not a Browse destination. Reuses
    /// `TaskListScreen`'s existing smart-view rendering; no new matching
    /// logic here.
    static let browsePages: [TaskPage] = [.upcoming, .anytime, .allTasks, .completed]

    private var browseSection: some View {
        Section(header: CompactSectionHeader(title: "Browse")) {
            ForEach(Self.browsePages) { page in
                browseRow(page)
            }
        }
        .listRowBackground(FlowTheme.surface(scheme))
    }

    @ViewBuilder
    private func browseRow(_ page: TaskPage) -> some View {
        if let view = page.smartView {
            let count = Self.taskPageContent(for: view, in: allTasks, now: flow?.now ?? Date()).count
            NavigationLink {
                TaskListScreen(source: .smartView(view))
            } label: {
                HStack(spacing: FlowSpacing.m) {
                    FlowNavigationGlyph(systemImage: view.symbolName, token: view.colour)

                    Text(page.title)
                        .font(FlowFont.body.weight(.semibold))
                        .foregroundStyle(FlowTheme.primaryText(scheme))

                    Spacer(minLength: FlowSpacing.s)

                    Text("\(count)")
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                }
                .padding(.vertical, FlowSpacing.xs)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("\(page.title), \(count)")
            .buttonStyle(FlowNavigationRowPressStyle())
        }
    }

    // MARK: - BUILD accordion

    private var projectsAccordion: some View {
        LibraryAccordionRow(
            title: "Projects",
            symbol: "folder",
            token: .lavender,
            count: projects.count,
            isExpanded: expansionBinding(for: "projects")
        ) {
            if projects.isEmpty {
                // Drops the mock's "in the full app" — that clause was the
                // demo apologising for being a demo. This is the full app.
                emptyRow("No projects yet. Branches of your map can become projects.")
            } else {
                ForEach(projects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingProjectDelete = project
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(FlowTheme.destructive)
                    }
                    #endif
                }
            }
        }
    }

    private var initiativesAccordion: some View {
        LibraryAccordionRow(
            title: "Initiatives",
            symbol: "scope",
            token: .violet,
            count: initiatives.count,
            isExpanded: expansionBinding(for: "initiatives")
        ) {
            if initiatives.isEmpty {
                emptyRow("No initiatives yet. Group projects under one to see them here.")
            } else {
                ForEach(initiatives) { initiative in
                    Button {
                        editingInitiative = initiative
                    } label: {
                        HStack(spacing: FlowSpacing.m) {
                            // An initiative's colour is user-chosen identity, so
                            // it stays on the glyph — but no filled tile behind
                            // it (fix 1, board task 138). `.base`, not `.onSoft`:
                            // `onSoft` is white for several tokens and is only
                            // legible sitting on that token's own tinted fill.
                            Image(systemName: initiative.iconName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(initiative.colour.base)
                                .frame(width: 36, height: 36)

                            Text(initiative.title)
                                .font(FlowFont.cardTitle)
                                .foregroundStyle(FlowTheme.primaryText(scheme))

                            Spacer(minLength: FlowSpacing.s)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private var projectDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingProjectDelete != nil },
            set: { if !$0 { pendingProjectDelete = nil } }
        )
    }

    private func deletePendingProject() {
        guard let project = pendingProjectDelete else { return }
        context.delete(project)
        try? context.save()
        pendingProjectDelete = nil
    }

    // MARK: - Notes accordion

    /// Notes shown in the accordion — active notes only, most recently
    /// updated first. Both the header's count and the unfolded rows read
    /// this one array, so they cannot disagree, the same principle
    /// `taskAccordionContent` already follows. `allNotes` is already sorted
    /// by `updatedAt` descending, so filtering preserves that order.
    static func noteAccordionContent(in notes: [Note]) -> [Note] {
        notes.filter { !$0.isArchived && !$0.isTrashed }
    }

    /// Tasks a note can attach to — a completed or cancelled task is not a
    /// sensible attach target. Exposed so a test can assert the filter
    /// without touching view state.
    static func noteAttachCandidates(in tasks: [FlowTask]) -> [FlowTask] {
        tasks
            .filter { $0.status.isOpen }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var noteCandidates: [FlowTask] {
        Self.noteAttachCandidates(in: allTasks)
    }

    private var notesAccordion: some View {
        let notes = Self.noteAccordionContent(in: allNotes)
        return LibraryAccordionRow(
            title: "Notes",
            symbol: "doc.text",
            token: .yellow,
            count: notes.count,
            isExpanded: expansionBinding(for: "notes")
        ) {
            if notes.isEmpty {
                emptyRow("No notes yet.")
            } else {
                ForEach(notes) { note in
                    NoteAttachRow(note: note, candidates: noteCandidates) { task in
                        toggleAttach(note: note, task: task)
                    } content: {
                        notePreviewRow(note)
                    } onShowPicker: {
                        attachmentPickerNote = note
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    /// One note's row: the accordion's own `.yellow` dot (not the mockup's
    /// leaked task colour — ruling 3, T6 stage 2), its title, and — only
    /// when attached to something — a trailing `On <task>` tag. Tapping
    /// opens the note itself (ruling 7).
    private func notePreviewRow(_ note: Note) -> some View {
        HStack(spacing: FlowSpacing.s) {
            Circle().fill(ColourToken.yellow.base).frame(width: 9, height: 9)
            Text(note.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)
            Spacer(minLength: FlowSpacing.s)
            if let task = note.task {
                Text("On \(task.title)")
                    // `durationChip` rather than a literal 10pt: it is the
                    // existing token for exactly this small bold tag, and it
                    // is built on `.caption2`, so it scales with Dynamic Type.
                    // A fixed size would not, which is an accessibility bug as
                    // well as a hard-coded size.
                    .font(FlowFont.durationChip)
                    .lineLimit(1)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .padding(.horizontal, FlowSpacing.s)
                    .padding(.vertical, FlowSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadius.tile, style: .continuous)
                            .fill(FlowTheme.surfaceWell(scheme))
                    )
            }
        }
        .contentShape(Rectangle())
        // Keep the compact row scannable without letting the note title touch
        // the accordion header or the next row at Dynamic Type sizes.
        .padding(.vertical, FlowSpacing.xs)
        .onTapGesture { inspectedNote = note }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens note")
    }

    /// Attach is single-select (ruling 4): tapping the already-attached
    /// task's chip detaches it (`task` and `current` share an id), choosing a
    /// different one re-assigns rather than adding. Exposed so a test can
    /// assert the toggle rule without touching view state or SwiftData.
    static func attachToggleResult(current: FlowTask?, tapped: FlowTask?) -> FlowTask? {
        current?.id == tapped?.id ? nil : tapped
    }

    private func toggleAttach(note: Note, task: FlowTask?) {
        note.task = Self.attachToggleResult(current: note.task, tapped: task)
        note.touch()
        try? context.save()
    }

    // MARK: - Expansion state

    private func expansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedRows.contains(key) },
            set: { isExpanded in
                if isExpanded { expandedRows.insert(key) } else { expandedRows.remove(key) }
            }
        )
    }

    /// The design's pastel token order for smart-view rows, cycled in order.
    private static let rowTokens: [ColourToken] = [
        .teal, .blue, .peach, .yellow, .lavender, .green, .pink,
    ]

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
    }

    /// The mock's row: soft token squircle with a solid dot, then the title.
    /// Still used by the LISTS section's plain `NavigationLink` rows.
    private func libraryLabel(_ title: String, symbol: String, token: ColourToken) -> some View {
        HStack(spacing: FlowSpacing.m) {
            // A user list's colour is its identity, so it stays on the glyph —
            // no filled tile behind it (fix 1, board task 138). `.base`, not
            // `.onSoft`: `onSoft` is white for several tokens and is only
            // legible sitting on that token's own tinted fill.
            FlowNavigationGlyph(systemImage: symbol, token: token)
            Text(title)
                .font(FlowFont.body.weight(.semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    /// Plain empty-state row inside an unfolded accordion — no `FlowEmptyState`
    /// symbol/title component, which is full-screen-empty-state weight and
    /// far too heavy for one unfolded row (HIG *Boxes*: no nested boxes).
    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(FlowFont.caption)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
    }
}
#endif
