import SwiftUI

/// A compulsory, cross-tab review for work left behind by a sealed day.
///
/// The sheet stays native and intentionally cannot be swiped away: every row
/// must be given an explicit home before the day can be closed.
struct RolloverReviewView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    private var review: RolloverReview? { flow?.pendingRolloverReview }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FlowSpacing.l) {
                    FlowEyebrow(sourceLabel)
                    Text("Remaining tasks")
                        .font(FlowFont.screenTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    Text("Each unfinished task needs a home before today can close.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))

                    if let review {
                        Text(reviewCountLabel(review))
                            .font(FlowFont.eyebrow)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                            .textCase(.uppercase)
                        ForEach(review.items) { item in
                            row(item)
                        }
                    }
                }
                .padding(.horizontal, FlowSpacing.screen)
                .padding(.top, FlowSpacing.l)
                .padding(.bottom, FlowSpacing.xl)
            }
            .background(FlowTheme.background(scheme).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                doneButton
                    .padding(.horizontal, FlowSpacing.screen)
                    .padding(.top, FlowSpacing.s)
                    .padding(.bottom, FlowSpacing.s)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .interactiveDismissDisabled(true)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var sourceLabel: String {
        guard let sourceDay = review?.sourceDay else { return "DAY CLOSE" }
        return sourceDay.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func reviewCountLabel(_ review: RolloverReview) -> String {
        let suffix = review.items.count == 1 ? "" : "s"
        return String(review.items.count) + " task" + suffix + " to review"
    }

    @ViewBuilder
    private func row(_ item: RolloverReviewItem) -> some View {
        FlowCard(padding: FlowSpacing.m) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: FlowSpacing.s) {
                    Image(systemName: item.resolution == nil ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(item.resolution == nil ? FlowTheme.tertiaryText(scheme) : FlowTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                        Text(item.taskTitle)
                            .font(FlowFont.cardTitle)
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                            .lineLimit(2)
                        Text(DurationFormatter.compact(minutes: item.minutes))
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }
                    Spacer(minLength: FlowSpacing.s)
                    if let resolution = item.resolution {
                        Text(resolution.label)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.accentDeep)
                    }
                }

                if item.resolution == nil {
                    HStack(spacing: FlowSpacing.s) {
                        Button("Tomorrow") {
                            flow?.resolveRolloverItem(item.id, with: .tomorrow)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FlowTheme.accent)
                        // Keep the visible clay control compact while giving
                        // the native button the full HIG hit target.
                        .frame(minHeight: 44)
                        .accessibilityLabel("Move " + item.taskTitle + " to tomorrow")

                        Menu {
                            Button("Backlog") {
                                flow?.resolveRolloverItem(item.id, with: .backlog)
                            }
                            Button("Delete", role: .destructive) {
                                flow?.resolveRolloverItem(item.id, with: .deleted)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                        }
                        .accessibilityLabel("More choices for " + item.taskTitle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var doneButton: some View {
        PrimaryActionButton("I'm done reviewing") {
            flow?.finishRolloverReview()
        }
        .disabled(!(review?.isComplete ?? false))
        .accessibilityHint(
            review?.isComplete == true
                ? "Closes the day review."
                : "Choose Tomorrow, Backlog or Delete for every task first."
        )
    }
}

private extension RolloverResolution {
    var label: String {
        switch self {
        case .tomorrow: "Tomorrow"
        case .backlog: "Backlog"
        case .deleted: "Deleted"
        }
    }
}
