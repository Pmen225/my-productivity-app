import SwiftUI
import UniformTypeIdentifiers

/// The day's timeline surface: hour gridlines, fixed calendar events, scheduled
/// Flowmap blocks and the manual drag/drop target.
///
/// This view has no scrolling of its own — it is a fixed-height region that
/// the caller places inside one shared `ScrollView`, so an "scroll to now"
/// anchor lives in the same coordinate space as the rest of the screen.
struct TimelineView: View {
    @Environment(\.colorScheme) private var scheme

    let dayStart: Date
    let dayEnd: Date
    let blocks: [TimelineBlock]
    let now: Date
    let lookupTask: (UUID) -> FlowTask?
    let onSchedule: (FlowTask, Date) -> Bool
    let onMove: (TaskSegment, Date) -> Bool
    let onRefusal: (String) -> Void

    @State private var previewStart: Date?
    @State private var previewMinutes: Int?

    /// The mock's density: roughly a minute to a point, so an hour reads as
    /// about 56pt. `TimelineBlockView` degrades its own detail level as blocks
    /// get shorter, rather than this view compensating with extra height.
    private let pointsPerMinute: CGFloat = 56.0 / 60.0
    private let gutterWidth: CGFloat = 50

    /// The mock's gutter reads "8:00", not "08:00" — a fixed pattern, because
    /// the reference design is locale-pinned to that shape.
    static let gutterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var totalMinutes: Int {
        max(1, Int(dayEnd.timeIntervalSince(dayStart) / 60))
    }

    private var totalHeight: CGFloat {
        CGFloat(totalMinutes) * pointsPerMinute
    }

    private func yOffset(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 60) * pointsPerMinute
    }

    /// Proportional height, less a seam so consecutive blocks read as separate.
    /// The floor is deliberately below the seam-adjusted height of a 15-minute
    /// block, so a block can never be drawn taller than the time it occupies.
    private func height(forMinutes minutes: Int) -> CGFloat {
        max(12, CGFloat(minutes) * pointsPerMinute - 2)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            hourGrid
            dropSurface

            ForEach(blocks) { block in
                let blockHeight = height(forMinutes: block.minutes)
                TimelineBlockView(block: block, height: blockHeight, now: now)
                    .padding(.leading, gutterWidth + FlowSpacing.s)
                    .padding(.trailing, FlowSpacing.xs)
                    .frame(height: blockHeight, alignment: .top)
                    .offset(y: yOffset(for: block.start))
                    .draggableTimelineBlock(block)
            }

            if let previewStart {
                insertionPreview(at: previewStart, minutes: previewMinutes ?? SchedulingEngine.snapMinutes)
            }

            nowLine

            // Anchor only — the current-time scroll target on iPhone.
            Color.clear
                .frame(width: 1, height: 1)
                .id("now-anchor")
                .offset(y: yOffset(for: now))
        }
        .frame(height: totalHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Grid

    private var hourMarks: [Date] {
        var marks: [Date] = []
        var cursor = dayStart
        let calendar = Calendar.current
        while cursor < dayEnd {
            marks.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return marks
    }

    private var hourGrid: some View {
        ForEach(hourMarks, id: \.self) { mark in
            HStack(alignment: .top, spacing: FlowSpacing.xs) {
                Text(Self.gutterFormatter.string(from: mark))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .frame(width: gutterWidth, alignment: .trailing)
                Rectangle()
                    .fill(FlowTheme.separator(scheme))
                    .frame(height: 1)
            }
            .offset(y: yOffset(for: mark) - 6)
        }
    }

    /// The live-time marker. Only drawn while `now` actually falls inside the
    /// rendered day — off the end of a short workday it would just float
    /// past the last hour mark.
    @ViewBuilder
    private var nowLine: some View {
        if now >= dayStart, now <= dayEnd {
            HStack(spacing: 0) {
                Text(Self.gutterFormatter.string(from: now))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, FlowSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(FlowTheme.accent))
                Circle()
                    .fill(FlowTheme.accent)
                    .frame(width: 7, height: 7)
                    .padding(.leading, FlowSpacing.xs)
                Rectangle()
                    .fill(FlowTheme.accent)
                    .frame(height: 2)
            }
            .padding(.leading, FlowSpacing.xs)
            .padding(.trailing, FlowSpacing.xs)
            .offset(y: yOffset(for: now) - 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Drop handling

    private var dropSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight)
            .onDrop(
                of: [.flowmapTimelineItem],
                delegate: TimelineDropDelegate(
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    pointsPerMinute: pointsPerMinute,
                    previewStart: $previewStart,
                    previewMinutes: $previewMinutes,
                    resolveSegment: resolveSegment,
                    resolveTask: lookupTask,
                    onSchedule: onSchedule,
                    onMove: onMove,
                    onRefusal: onRefusal
                )
            )
    }

    private func resolveSegment(_ id: UUID) -> TaskSegment? {
        blocks.first { $0.segment?.id == id }?.segment
    }

    private func insertionPreview(at start: Date, minutes: Int) -> some View {
        let previewHeight = height(forMinutes: minutes)
        return RoundedRectangle(cornerRadius: min(FlowRadius.small, previewHeight / 2), style: .continuous)
            .strokeBorder(FlowTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .frame(height: previewHeight)
            .padding(.leading, gutterWidth + FlowSpacing.s)
            .padding(.trailing, FlowSpacing.xs)
            .offset(y: yOffset(for: start))
            .allowsHitTesting(false)
    }
}
