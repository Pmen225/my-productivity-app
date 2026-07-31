import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Floating tab bar

/// One entry in a `FlowTabBar` — a destination's tag, label and icon.
///
/// Decision 1b (2026-07-29) reverses subtask 37's `≡` glass menu back to a
/// tab bar. `PhoneRootView` now drives the *real* native `TabView`/`.tabItem`
/// chrome directly (so it stays a genuinely native tab bar, not a custom
/// overlay hidden behind the system one) and restyles it with
/// `.tint(FlowTheme.accent)` plus a material `.toolbarBackground`. This type
/// is restored here — matching its pre-subtask-37 shape exactly — as the
/// design system's record of the floating-pill styling those native
/// modifiers are matched to; nothing currently instantiates it.
public struct FlowTabBarItem<Tag: Hashable>: Identifiable {
    public let id: Tag
    public let title: String
    public let systemImage: String

    public init(id: Tag, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// The floating glass tab bar: a rounded pill inset from the screen edges,
/// icon over a small tracked label, the selected item in the accent colour.
///
/// Presentational only — the caller owns the `TabView`/`NavigationStack`
/// switching and simply hides the system tab bar, so this can sit as an
/// overlay above the content instead of consuming its own safe-area slice.
public struct FlowTabBar<Tag: Hashable>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var selection: Tag
    private let items: [FlowTabBarItem<Tag>]

    public init(selection: Binding<Tag>, items: [FlowTabBarItem<Tag>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.id == selection
                Button {
                    select(item.id)
                } label: {
                    VStack(spacing: FlowSpacing.xs) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(item.title)
                            .font(FlowFont.chromeLabel)
                    }
                    .foregroundStyle(isSelected ? FlowTheme.accent : FlowTheme.tertiaryText(scheme))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.s)
        .flowGlass(radius: FlowRadius.chrome)
    }

    private func select(_ tag: Tag) {
        guard tag != selection else { return }
        if reduceMotion {
            selection = tag
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selection = tag
            }
        }
    }
}

// MARK: - Floating circular button

/// A floating circular chrome control. It can expose a secondary Assistant
/// path without adding a competing second control to the screen corner.
public struct FlowFloatingButton: View {
    private let systemImage: String
    private let diameter: CGFloat
    private let background: Color
    private let foreground: Color
    private let shadowColor: Color
    private let accessibilityLabel: String
    private let action: () -> Void
    private let badgeSystemImage: String?
    private let assistantAction: (() -> Void)?
    private let hapticsEnabled: Bool

    public init(
        systemImage: String,
        diameter: CGFloat,
        background: Color,
        foreground: Color,
        shadowColor: Color,
        accessibilityLabel: String,
        badgeSystemImage: String? = nil,
        assistantAction: (() -> Void)? = nil,
        hapticsEnabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.diameter = diameter
        self.background = background
        self.foreground = foreground
        self.shadowColor = shadowColor
        self.accessibilityLabel = accessibilityLabel
        self.badgeSystemImage = badgeSystemImage
        self.assistantAction = assistantAction
        self.hapticsEnabled = hapticsEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(foreground)

                if let badgeSystemImage {
                    Image(systemName: badgeSystemImage)
                        .font(.system(size: diameter * 0.19, weight: .semibold))
                        .foregroundStyle(foreground)
                        .frame(width: diameter * 0.34, height: diameter * 0.34)
                        .background(Circle().fill(FlowTheme.popoverSurface))
                        .padding(diameter * 0.06)
                }
            }
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(background))
            .shadow(color: shadowColor, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(assistantAction == nil ? "" : "Double tap to create. Use the Open Assistant custom action for help.")
        .accessibilityAction(named: "Open Assistant") {
            assistantAction?()
        }
        // A high-priority recogniser cancels the Button's release action once
        // the hold succeeds. A short tap still falls through to the Button,
        // so a long press cannot swallow the next Create tap.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: 44)
                .onEnded { _ in activateAssistant() }
        )
    }

    private func activateAssistant() {
        guard let assistantAction else { return }
        #if os(iOS)
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
        assistantAction()
    }
}

// MARK: - Screen title

/// The mock's quiet centred screen title — 15pt bold, sitting in the nav
/// bar's principal slot instead of the system's large left-aligned title.
///
/// iPhone only. The mock is an iPhone design, and on macOS the window already
/// shows `navigationTitle` in its title bar — adding a principal toolbar item
/// there would simply print the same words twice. Callers keep their own
/// `.navigationTitle` so the back-button label and the VoiceOver heading
/// survive on both platforms.
private struct FlowScreenTitle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let title: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(FlowFont.screenTitleCompact)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .accessibilityAddTraits(.isHeader)
                }
            }
        #else
        content
        #endif
    }
}

public extension View {
    /// See `FlowScreenTitle`.
    func flowScreenTitle(_ title: String) -> some View {
        modifier(FlowScreenTitle(title: title))
    }
}

// MARK: - Modal dialog

/// The mock's centred frosted sheet: eyebrow, title, one short explanatory
/// line, and a full-width clay CTA. Used for interruptions that need a single
/// decision — clocking in, planning before a task starts — never for forms.
public struct FlowDialog: View {
    @Environment(\.colorScheme) private var scheme

    private let eyebrow: String?
    private let title: String
    private let message: String
    private let ctaTitle: String
    private let isDestructive: Bool
    private let cancelTitle: String?
    private let ctaAction: () -> Void
    private let cancelAction: (() -> Void)?

    /// `eyebrow` is optional because the mock's delete card has none, and
    /// `cancelTitle` because most of these dialogs are single-decision.
    public init(
        eyebrow: String? = nil,
        title: String,
        message: String,
        ctaTitle: String,
        isDestructive: Bool = false,
        cancelTitle: String? = nil,
        ctaAction: @escaping () -> Void,
        cancelAction: (() -> Void)? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.isDestructive = isDestructive
        self.cancelTitle = cancelTitle
        self.ctaAction = ctaAction
        self.cancelAction = cancelAction
    }

    public var body: some View {
        VStack(alignment: .center, spacing: FlowSpacing.xs) {
            if let eyebrow {
                FlowEyebrow(eyebrow, tint: FlowTheme.accent)
            }
            Text(title)
                .font(FlowFont.dialogTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, FlowSpacing.xxs)
            Text(message)
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FlowSpacing.xxs)

            PrimaryActionButton(
                ctaTitle,
                tint: isDestructive ? FlowTheme.destructive : FlowTheme.accentFill,
                action: ctaAction
            )
            .padding(.top, FlowSpacing.m)

            if let cancelTitle {
                Button(cancelTitle) { cancelAction?() }
                    .buttonStyle(.plain)
                    .font(FlowFont.body)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(FlowSpacing.l)
        .frame(maxWidth: 320)
        .flowGlass(radius: FlowRadius.sheet)
        .accessibilityElement(children: .contain)
    }
}

/// Presents a `FlowDialog` (or any centred modal) over a dimmed scrim,
/// matching the mock's Clock-in / Plan-gate treatment. The caller supplies
/// the dialog content and owns the `isPresented` state — dismissal is the
/// dialog's own CTA, never a tap-outside, since these are single-decision
/// interruptions rather than dismissable sheets.
private struct FlowDialogOverlay<DialogContent: View>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPresented: Bool
    let dialog: DialogContent

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    FlowTheme.popoverSurface.opacity(0.28)
                        .ignoresSafeArea()
                    dialog
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: isPresented)
    }
}

public extension View {
    /// See `FlowDialogOverlay`.
    func flowDialogOverlay<DialogContent: View>(
        isPresented: Bool,
        @ViewBuilder dialog: () -> DialogContent
    ) -> some View {
        modifier(FlowDialogOverlay(isPresented: isPresented, dialog: dialog()))
    }

    /// The mock's delete confirmation: one glass card, everywhere, replacing
    /// the `.confirmationDialog` and `.alert` the app used to mix.
    ///
    /// Presented as a sheet rather than an overlay because callers are list
    /// rows and canvas nodes, whose bounds would clip a centred card.
    func flowDeleteConfirmation(
        isPresented: Binding<Bool>,
        itemTitle: String,
        hasChildren: Bool,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            FlowDeleteConfirmation(
                isPresented: isPresented,
                itemTitle: itemTitle,
                hasChildren: hasChildren,
                onDelete: onDelete
            )
        )
    }
}

/// The mock's two delete messages, branched on whether anything hangs off the
/// item being deleted.
public enum FlowDeleteMessage {
    public static func text(hasChildren: Bool) -> String {
        hasChildren
            ? "The project and its tasks come off the map, schedule and inbox."
            : "It comes off the map, schedule and inbox."
    }
}

/// See `View.flowDeleteConfirmation(isPresented:itemTitle:hasChildren:onDelete:)`.
private struct FlowDeleteConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let itemTitle: String
    let hasChildren: Bool
    let onDelete: () -> Void

    /// Taken once, when the card opens. Callers whose pending item clears on
    /// dismissal would otherwise blink the card to `Delete “”?` for the length
    /// of the closing animation.
    @State private var shown: (title: String, hasChildren: Bool) = ("", false)

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presenting in
                if presenting { shown = (itemTitle, hasChildren) }
            }
            .sheet(isPresented: $isPresented) { card }
    }

    private var card: some View {
        ZStack {
            FlowTheme.popoverSurface.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            FlowDialog(
                title: "Delete “\(shown.title)”?",
                message: FlowDeleteMessage.text(hasChildren: shown.hasChildren),
                ctaTitle: "Delete",
                isDestructive: true,
                cancelTitle: "Cancel",
                // Delete first, dismiss second: a caller whose binding clears
                // its pending item on dismissal would otherwise have nothing
                // left to delete by the time the action ran.
                ctaAction: {
                    onDelete()
                    isPresented = false
                },
                cancelAction: { isPresented = false }
            )
        }
        .presentationBackground(.clear)
    }
}

// MARK: - Popover menu

/// One selectable row in a `FlowPopoverMenu`.
public struct FlowPopoverOption<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String

    public init(id: ID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Which surface a `FlowPopoverMenu` sits on. Both read from the reference
/// screenshots: a dark card over a light map background, and a white card
/// over a light screen with its chosen row filled clay.
public enum FlowPopoverStyle {
    case dark
    case light
}

/// The mock's rounded popover list — generous rows, a tick or a clay fill on
/// the chosen one. Presented with the system `.popover(isPresented:)`
/// modifier so dismissal, Escape and VoiceOver's dismiss gesture stay free;
/// the rows themselves are plain `Button`s, not a system `Menu`, because a
/// `Menu`'s rows cannot be recoloured to match the mock. Every row keeps its
/// own accessibility selection state, so VoiceOver and Full Keyboard Access
/// see an ordinary list of buttons either way.
public struct FlowPopoverMenu<ID: Hashable>: View {
    @Environment(\.colorScheme) private var scheme

    private let style: FlowPopoverStyle
    private let options: [FlowPopoverOption<ID>]
    private let selection: ID?
    private let onSelect: (ID) -> Void

    public init(
        style: FlowPopoverStyle,
        options: [FlowPopoverOption<ID>],
        selection: ID?,
        onSelect: @escaping (ID) -> Void
    ) {
        self.style = style
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 2) {
            ForEach(options) { option in
                row(option)
            }
        }
        .padding(FlowSpacing.xs)
        .frame(minWidth: 170)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(style == .dark ? FlowTheme.popoverSurface : FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.glassBorder(scheme), lineWidth: style == .dark ? 0 : 1)
        )
        .shadow(color: FlowTheme.shadow(scheme), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func row(_ option: FlowPopoverOption<ID>) -> some View {
        let isSelected = option.id == selection
        return Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: FlowSpacing.s) {
                Text(option.title)
                    .font(FlowFont.body)
                    .foregroundStyle(rowForeground(isSelected: isSelected))
                Spacer(minLength: FlowSpacing.s)
                if style == .dark, isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                }
            }
            .padding(.horizontal, FlowSpacing.m)
            // HIG override 1: the mock's rows read shorter than this on the
            // pixel reference; held at 44pt so every row clears the minimum
            // tappable height regardless of Dynamic Type.
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(style == .light && isSelected ? FlowTheme.accentFill : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func rowForeground(isSelected: Bool) -> Color {
        switch style {
        case .dark: Color.white.opacity(0.94)
        case .light: isSelected ? .white : FlowTheme.primaryText(scheme)
        }
    }
}

/// The create sheet's text-input shape: surface fill, hairline border, the
/// mock's 12pt corner. Shared by the name, subtask and note fields so they
/// cannot drift apart.
private struct FieldChrome: ViewModifier {
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .padding(FlowSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(FlowTheme.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
            )
    }
}

// MARK: - Create sheet

/// What a `FlowCreateSheet` is making.
public enum FlowCreateKind: String, CaseIterable, Identifiable, Sendable {
    case task, project, initiative

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .task: "Task"
        case .project: "Project"
        case .initiative: "Initiative"
        }
    }

    /// An initiative is a goal, not a thing with a name, so the mockup prompts
    /// for one by example instead of the plain `<Kind> name…` pattern.
    public var namePlaceholder: String {
        switch self {
        case .task, .project: "\(title) name…"
        case .initiative: "Goal — e.g. \"Ship my portfolio\""
        }
    }

    /// The mockup explains what the kind will do once created; only the two
    /// container kinds carry a line.
    public var explanation: String? {
        switch self {
        case .task: nil
        case .project: "A project becomes a branch on your map. Attached projects feed the initiative's XP and goal bar."
        case .initiative: "An initiative is the goal at the root of your map. Projects and tasks under it feed its XP — finish them all to complete it."
        }
    }
}

/// One project chip: its colour dot and label.
public struct FlowCreateChipOption: Identifiable {
    public let id: UUID
    public let title: String
    public let colour: ColourToken

    public init(id: UUID, title: String, colour: ColourToken) {
        self.id = id
        self.title = title
        self.colour = colour
    }
}

/// The mock's "New" bottom sheet.
///
/// Presentation only: it holds no SwiftData context and performs no
/// creation itself. The caller owns every value as a binding and supplies
/// `onCreate`, so this can sit in front of whichever screen's own creation
/// path is already live without a second implementation of it.
public struct FlowCreateSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var kind: FlowCreateKind
    @Binding private var title: String
    @Binding private var minutes: Int
    @Binding private var projectID: UUID?
    /// Whether a due date is set at all — the sheet starts with no due date,
    /// same as duration and project start with a default rather than "none".
    @Binding private var hasDue: Bool
    @Binding private var dueDate: Date
    @Binding private var recurrence: RecurrenceFrequency
    /// Subtask titles typed here before the task exists. Plain strings rather
    /// than `Subtask` models: nothing is inserted into the store until Create
    /// is pressed, so an abandoned sheet leaves nothing behind.
    @Binding private var subtaskTitles: [String]
    @Binding private var note: String
    /// The goal a new project is being filed under, if any.
    @Binding private var initiativeID: UUID?
    private let durations: [Int]
    private let projects: [FlowCreateChipOption]
    private let initiatives: [FlowCreateChipOption]
    /// Hidden for kinds where a duration and a parent project make no sense
    /// — a project itself is not scheduled and does not belong to another.
    private let showsDurationAndProject: Bool
    private let onClose: () -> Void
    private let onCreate: () -> Void

    /// The subtask being typed. Local, because a half-typed row is not part of
    /// what the sheet is making until return commits it.
    @State private var draftSubtask = ""

    public init(
        kind: Binding<FlowCreateKind>,
        title: Binding<String>,
        minutes: Binding<Int>,
        projectID: Binding<UUID?>,
        hasDue: Binding<Bool>,
        dueDate: Binding<Date>,
        recurrence: Binding<RecurrenceFrequency>,
        subtaskTitles: Binding<[String]>,
        note: Binding<String>,
        initiativeID: Binding<UUID?>,
        durations: [Int] = FlowDurationWheel.defaultOptions,
        projects: [FlowCreateChipOption],
        initiatives: [FlowCreateChipOption],
        showsDurationAndProject: Bool = true,
        onClose: @escaping () -> Void,
        onCreate: @escaping () -> Void
    ) {
        self._kind = kind
        self._title = title
        self._minutes = minutes
        self._projectID = projectID
        self._hasDue = hasDue
        self._dueDate = dueDate
        self._recurrence = recurrence
        self._subtaskTitles = subtaskTitles
        self._note = note
        self._initiativeID = initiativeID
        self.initiatives = initiatives
        self.durations = durations
        self.projects = projects
        self.showsDurationAndProject = showsDurationAndProject
        self.onClose = onClose
        self.onCreate = onCreate
    }

    public var body: some View {
        // Scrolls, because this sheet's height is data-dependent: the moment
        // real projects existed the PROJECT chip row pushed Create below the
        // medium detent's fold, and with a plain VStack there was no way to
        // reach it — not for a test, and not for a person. Growing content
        // must be scrollable rather than trusting it to fit.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(FlowTheme.background(scheme))
        .clipShape(
            .rect(topLeadingRadius: FlowRadius.large, topTrailingRadius: FlowRadius.large)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            header
            kindPicker
            titleField
            if showsDurationAndProject {
                durationSection
                if !projects.isEmpty {
                    projectSection
                }
            }
            // Only a task breaks into subtasks and carries a note — a project
            // or an initiative is the thing those hang off, not a unit of work.
            // A due date is the same: only a task is ever scheduled or dated.
            if kind == .task {
                dueSection
                repeatSection
                subtasksSection
                noteSection
            }
            // A project files under a goal; a task reaches its goal through
            // whichever project it belongs to, so it does not ask twice.
            if kind == .project {
                initiativeSection
            }
            if let explanation = kind.explanation {
                Text(explanation)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryActionButton("Create", action: onCreate)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(FlowSpacing.screen)
    }

    private var header: some View {
        HStack {
            Text("New")
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    // HIG override 1: a 14pt glyph on its own reads well
                    // under 44pt — the tappable area is grown around it
                    // rather than the ✕ itself being scaled up.
                    .flowHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var kindPicker: some View {
        HStack(spacing: FlowSpacing.xxs) {
            ForEach(FlowCreateKind.allCases) { option in
                let isSelected = option == kind
                Button {
                    select(kind: option)
                } label: {
                    Text(option.title)
                        .font(FlowFont.secondary.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FlowSpacing.s)
                        .background(Capsule().fill(isSelected ? FlowTheme.accentFill : .clear))
                        .foregroundStyle(isSelected ? .white : FlowTheme.secondaryText(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(FlowSpacing.xxs)
        .background(Capsule().fill(FlowTheme.surfaceSunken(scheme)))
    }

    private var titleField: some View {
        TextField(kind.namePlaceholder, text: $title)
            .font(FlowFont.body)
            .modifier(FieldChrome(scheme: scheme))
            .accessibilityLabel("\(kind.title) name")
    }

    /// The mock's `SUBTASKS` block: what is already listed, each removable,
    /// then one input that adds a row on return and stays ready for the next.
    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Subtasks")
            ForEach(Array(subtaskTitles.enumerated()), id: \.offset) { index, subtask in
                HStack(spacing: FlowSpacing.s) {
                    Text(subtask)
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    Spacer(minLength: 0)
                    Button {
                        subtaskTitles.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            // HIG override 1 again: small glyph, grown target.
                            .flowHitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(subtask)")
                }
            }
            TextField("Add a subtask + return…", text: $draftSubtask)
                .font(FlowFont.secondary)
                .submitLabel(.done)
                .onSubmit(addDraftSubtask)
                .modifier(FieldChrome(scheme: scheme))
                .accessibilityLabel("Add a subtask")
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Note")
            TextField("Optional note — attaches to this task…", text: $note, axis: .vertical)
                .font(FlowFont.secondary)
                .lineLimit(1...4)
                .modifier(FieldChrome(scheme: scheme))
                .accessibilityLabel("Note")
        }
    }

    private func addDraftSubtask() {
        let trimmed = draftSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        draftSubtask = ""
    }

    /// The wheel is still the same adjustable control; the prompt names the
    /// time being priced without adding a second explanatory caption.
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Worth · how much of your time?")
            FlowDurationWheel(minutes: $minutes, options: durations)
        }
    }

    /// Mirrors `QuickAddTaskView.dateControl`: a collapsed pill that expands
    /// into a date+time picker. Self-labelled like `durationSection` rather
    /// than wrapped in an eyebrow — the mock puts the label on the control,
    /// not above it.
    private var dueSection: some View {
        Group {
            if hasDue {
                HStack(spacing: FlowSpacing.xs) {
                    Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                    DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    Button {
                        hasDue = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear due date")
                }
                .foregroundStyle(FlowTheme.primaryText(scheme))
            } else {
                Button {
                    hasDue = true
                } label: {
                    HStack(spacing: FlowSpacing.xs) {
                        Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                        Text("Due").font(FlowFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add due date")
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 44)
        .background(Capsule().fill(FlowTheme.surface(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
    }

    /// Same self-labelled capsule idiom as `dueSection` — one control, no eyebrow.
    private var repeatSection: some View {
        HStack(spacing: FlowSpacing.xs) {
            Image(systemName: "repeat").font(.system(size: 13, weight: .semibold))
            Picker("Repeat", selection: $recurrence) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .foregroundStyle(FlowTheme.primaryText(scheme))
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 44)
        .background(Capsule().fill(FlowTheme.surface(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Project")
            FlowChipWrap(spacing: FlowSpacing.s) {
                ForEach(projects) { project in
                    projectChip(project)
                }
            }
        }
    }

    /// The mock's `INITIATIVE` row: the goals a new project can be filed
    /// under, with an explicit `None` rather than a nothing-selected state the
    /// user has to infer.
    private var initiativeSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Initiative")
            FlowChipWrap(spacing: FlowSpacing.s) {
                chip(title: "None", colour: nil, isSelected: initiativeID == nil) {
                    animated { initiativeID = nil }
                }
                ForEach(initiatives) { initiative in
                    chip(
                        title: initiative.title,
                        colour: initiative.colour,
                        isSelected: initiative.id == initiativeID
                    ) {
                        animated { initiativeID = initiative.id }
                    }
                }
            }
        }
    }

    private func projectChip(_ project: FlowCreateChipOption) -> some View {
        chip(
            title: project.title,
            colour: project.colour,
            isSelected: project.id == projectID
        ) {
            select(project: project.id)
        }
    }

    private func chip(
        title: String,
        colour: ColourToken?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FlowSpacing.xs) {
                if let colour {
                    Circle().fill(colour.base).frame(width: 8, height: 8)
                }
                Text(title).font(FlowFont.secondary)
            }
            .padding(.horizontal, FlowSpacing.m)
            // HIG override 1: same reasoning as the duration chips above.
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? FlowTheme.accentFill : FlowTheme.surface(scheme)))
            .foregroundStyle(isSelected ? .white : FlowTheme.primaryText(scheme))
            .overlay(
                Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Selection, honouring Reduce Motion

    private func select(kind newKind: FlowCreateKind) {
        animated { kind = newKind }
    }

    private func select(project id: UUID) {
        animated { projectID = (projectID == id) ? nil : id }
    }

    private func animated(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86), body)
        }
    }
}

/// Wraps chips onto as many lines as they need — the create sheet's project
/// row can hold more chips than one line fits, unlike every other chip row in
/// the app which scrolls horizontally instead.
private struct FlowChipWrap: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
