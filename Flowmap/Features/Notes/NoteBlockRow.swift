import SwiftUI

/// One editable block. `@Bindable` binds straight to the SwiftData object so
/// typing writes directly into the model — no separate view-model copy that
/// could drift out of sync.
struct NoteBlockRow: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var block: NoteBlock

    /// Position among sibling `.numbered` blocks, for a real "1. 2. 3." label
    /// even though nothing but order is actually persisted.
    let numberInList: Int?
    let focusedBlockID: FocusState<UUID?>.Binding

    /// Fires on every keystroke; the editor debounces the actual disk write.
    let onTextChanged: () -> Void
    /// Return key: insert a new block after this one and focus it.
    let onReturn: () -> Void
    /// Backspace on an already-empty block: delete it and focus the previous one.
    let onBackspaceOnEmpty: () -> Void
    /// `/` typed as the very first character of an empty block: open the type menu.
    let onSlashTrigger: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: FlowSpacing.s) {
            marker
            if block.type == .divider {
                Divider()
                    .padding(.vertical, FlowSpacing.s)
            } else {
                TextField("", text: textBinding, axis: .vertical)
                    .font(font)
                    .foregroundStyle(
                        block.type == .checklist && block.isChecked
                            ? FlowTheme.secondaryText(scheme)
                            : FlowTheme.primaryText(scheme)
                    )
                    .focused(focusedBlockID, equals: block.id)
                    .onKeyPress(.return) {
                        onReturn()
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard block.text.isEmpty else { return .ignored }
                        onBackspaceOnEmpty()
                        return .handled
                    }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { block.text },
            set: { newValue in
                // A lone leading "/" on an empty block opens the type menu
                // instead of being typed as text.
                if block.text.isEmpty, newValue == "/" {
                    onSlashTrigger()
                    return
                }
                block.text = newValue
                block.touch()
                onTextChanged()
            }
        )
    }

    @ViewBuilder
    private var marker: some View {
        switch block.type {
        case .checklist:
            Button {
                block.isChecked.toggle()
                block.touch()
                onTextChanged()
            } label: {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(block.isChecked ? FlowTheme.accent : FlowTheme.secondaryText(scheme))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        case .bullet:
            Circle()
                .fill(FlowTheme.secondaryText(scheme))
                .frame(width: 5, height: 5)
                .padding(.top, 9)
        case .numbered:
            Text("\(numberInList ?? 1).")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(minWidth: 18, alignment: .trailing)
        case .quote, .callout:
            Image(systemName: block.type.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .padding(.top, 3)
        case .paragraph, .heading1, .heading2, .divider:
            Color.clear.frame(width: 0)
        }
    }

    private var font: Font {
        switch block.type {
        case .heading1: FlowFont.screenTitle
        case .heading2: FlowFont.sectionTitle
        case .quote, .callout: FlowFont.secondary.italic()
        default: FlowFont.body
        }
    }
}
