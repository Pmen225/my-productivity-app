import SwiftData
import SwiftUI

/// The nonmodal "mini assistant dock" the shell's orb opens first (decision
/// 26, HIG ruling 1): a compact, always-dark-glass surface for quick chat.
/// `⤢` hands off to the full `AssistantScreen`; `✕` dismisses. Presentation
/// (detents, drag indicator, background interaction) lives on the `.sheet`
/// modifier in `PhoneRootView`, which owns this view's presentation state —
/// this file only draws the panel's content.
struct AssistantMiniDockView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \AssistantThread.updatedAt, order: .reverse) private var threads: [AssistantThread]

    @State private var activeThread: AssistantThread?
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if let flow, let activeThread {
                    AssistantConversationView(
                        thread: activeThread,
                        flow: flow,
                        background: .clear,
                        onConnectTapped: onExpand
                    )
                    .id(activeThread.id)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(dockBackground)
        .clipShape(RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous))
        // The mockup's dock is a fixed dark-glass panel in both schemes —
        // matches `FlowTheme.popoverSurface`'s own "dark in both schemes"
        // convention, so text drawn via `FlowTheme.*Text(scheme)` stays
        // legible without threading a second colour path through the
        // (reused) conversation view.
        .environment(\.colorScheme, .dark)
        .onAppear {
            guard activeThread == nil else { return }
            activeThread = threads.first(where: { !$0.isArchived }) ?? makeThread()
        }
    }

    private var header: some View {
        HStack(spacing: FlowSpacing.s) {
            Text("✦ Assistant")
                .font(FlowFont.cardTitle.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: FlowSpacing.s)
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white)
            }
            .flowHitTarget()
            .accessibilityLabel("Expand to full screen")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .flowHitTarget()
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.top, FlowSpacing.m)
        .padding(.bottom, FlowSpacing.s)
    }

    private var dockBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(FlowTheme.popoverSurface.opacity(0.82))
        }
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @discardableResult
    private func makeThread() -> AssistantThread {
        let thread = AssistantThread()
        context.insert(thread)
        try? context.save()
        return thread
    }
}
