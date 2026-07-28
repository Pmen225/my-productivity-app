import SwiftUI

// MARK: - Floating tab bar

/// One entry in a `FlowTabBar` — a destination's tag, label and icon.
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

/// A floating circular chrome control — the create FAB and the assistant
/// orb are both this, differing only in size, fill and glyph.
public struct FlowFloatingButton: View {
    @Environment(\.colorScheme) private var scheme

    private let systemImage: String
    private let diameter: CGFloat
    private let background: Color
    private let foreground: Color
    private let shadowColor: Color
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(
        systemImage: String,
        diameter: CGFloat,
        background: Color,
        foreground: Color,
        shadowColor: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.diameter = diameter
        self.background = background
        self.foreground = foreground
        self.shadowColor = shadowColor
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
                .shadow(color: shadowColor, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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

    private let eyebrow: String
    private let title: String
    private let message: String
    private let ctaTitle: String
    private let ctaAction: () -> Void

    public init(
        eyebrow: String,
        title: String,
        message: String,
        ctaTitle: String,
        ctaAction: @escaping () -> Void
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.ctaAction = ctaAction
    }

    public var body: some View {
        VStack(alignment: .center, spacing: FlowSpacing.xs) {
            FlowEyebrow(eyebrow, tint: FlowTheme.accent)
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

            PrimaryActionButton(ctaTitle, action: ctaAction)
                .padding(.top, FlowSpacing.m)
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
}

/// One project chip: its colour dot and label.
public struct FlowCreateProjectOption: Identifiable {
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
    private let durations: [Int]
    private let projects: [FlowCreateProjectOption]
    /// Hidden for kinds where a duration and a parent project make no sense
    /// — a project itself is not scheduled and does not belong to another.
    private let showsDurationAndProject: Bool
    private let onClose: () -> Void
    private let onCreate: () -> Void

    public init(
        kind: Binding<FlowCreateKind>,
        title: Binding<String>,
        minutes: Binding<Int>,
        projectID: Binding<UUID?>,
        durations: [Int] = [15, 25, 30, 45, 60],
        projects: [FlowCreateProjectOption],
        showsDurationAndProject: Bool = true,
        onClose: @escaping () -> Void,
        onCreate: @escaping () -> Void
    ) {
        self._kind = kind
        self._title = title
        self._minutes = minutes
        self._projectID = projectID
        self.durations = durations
        self.projects = projects
        self.showsDurationAndProject = showsDurationAndProject
        self.onClose = onClose
        self.onCreate = onCreate
    }

    public var body: some View {
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
            PrimaryActionButton("Create", action: onCreate)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(FlowSpacing.screen)
        .background(FlowTheme.background(scheme))
        .clipShape(
            .rect(topLeadingRadius: FlowRadius.large, topTrailingRadius: FlowRadius.large)
        )
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
        TextField("\(kind.title) name…", text: $title)
            .font(FlowFont.body)
            .padding(FlowSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(FlowTheme.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
            )
            .accessibilityLabel("\(kind.title) name")
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Duration")
            HStack(spacing: FlowSpacing.s) {
                ForEach(durations, id: \.self) { value in
                    durationChip(value)
                }
            }
        }
    }

    private func durationChip(_ value: Int) -> some View {
        let isSelected = value == minutes
        return Button {
            select(minutes: value)
        } label: {
            Text(DurationFormatter.compact(minutes: value))
                .font(FlowFont.durationChip)
                .foregroundStyle(isSelected ? .white : FlowTheme.primaryText(scheme))
                .padding(.horizontal, FlowSpacing.m)
                // HIG override 1: the mock's chips are visibly shorter than
                // 44pt; the fill stays chip-sized, the hit area does not.
                .frame(minHeight: 44)
                .background(Capsule().fill(isSelected ? FlowTheme.accentFill : FlowTheme.surface(scheme)))
                .overlay(
                    Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DurationFormatter.spoken(minutes: value))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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

    private func projectChip(_ project: FlowCreateProjectOption) -> some View {
        let isSelected = project.id == projectID
        return Button {
            select(project: project.id)
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Circle().fill(project.colour.base).frame(width: 8, height: 8)
                Text(project.title).font(FlowFont.secondary)
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

    private func select(minutes value: Int) {
        animated { minutes = value }
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
