import SwiftUI

/// One field, one button. The system `TextField` gives dictation and Scribble
/// for free on watchOS, so there is no bespoke input UI to build here — only
/// forward whatever came in as a `.capture` command.
struct WatchCaptureView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var text = ""
    @State private var showsConfirmation = false

    var body: some View {
        VStack(spacing: FlowSpacing.m) {
            Text("Capture")
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))

            TextField("Add a thought", text: $text)
                .accessibilityLabel("Capture text")

            Button(action: send) {
                Text("Send")
                    .font(FlowFont.secondary.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FlowSpacing.s)
                    .background(Capsule().fill(FlowTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send to inbox")

            // Reserves its row whether shown or not, so the button above never
            // shifts position when the confirmation appears and fades.
            Text("Sent")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .opacity(showsConfirmation ? 1 : 0)
                .accessibilityHidden(!showsConfirmation)
        }
        .padding(.horizontal, FlowSpacing.m)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.send(.capture(trimmed))
        text = ""
        withAnimation { showsConfirmation = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showsConfirmation = false }
        }
    }
}
