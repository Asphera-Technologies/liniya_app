import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct FocusWidget: Widget {
    private let accent = Color(red: 0.24, green: 0.61, blue: 0.94)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            VStack(spacing: 12) {
                timerRow(context)
                titleRow(context.state)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .systemBackground))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        timerRow(context)
                        titleRow(context.state)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                focusMark(context.state, size: 20)
            } compactTrailing: {
                compactCountdown(context.state)
                    .font(.caption2)
                    .frame(width: 88, alignment: .trailing)
                    .foregroundStyle(accent)
            } minimal: {
                focusMark(context.state, size: 20)
            }
            .keylineTint(accent)
        }
    }

    private func timerRow(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            controls(context)
            FocusTimerReadout(content: countdown(context.state))
                .foregroundStyle(accent)
        }
        .frame(minHeight: 52)
    }

    private func titleRow(_ state: FocusActivityAttributes.ContentState) -> some View {
        HStack(spacing: 8) {
            progress(state, size: 24)
            taskTitle(state)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func taskTitle(_ state: FocusActivityAttributes.ContentState) -> some View {
        Text(state.title)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(state.title)
    }

    private func compactCountdown(_ state: FocusActivityAttributes.ContentState) -> some View {
        let format = Date.ComponentsFormatStyle(style: .abbreviated, fields: [.hour, .minute])
        return Group {
            if let seconds = state.pausedSeconds {
                let start = state.endsAt.addingTimeInterval(-Double(max(0, seconds)))
                Text(start..<state.endsAt, format: format)
            } else {
                Text(.dateRange(endingAt: state.endsAt), format: format)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("Осталось")
    }

    private func countdown(_ state: FocusActivityAttributes.ContentState) -> some View {
        Group {
            if let seconds = state.pausedSeconds {
                Text(Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2))))
            } else {
                Text(timerInterval: state.countdownStart...state.endsAt, countsDown: true)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("Осталось")
    }

    private func progress(_ state: FocusActivityAttributes.ContentState, size: CGFloat) -> some View {
        ZStack {
            Group {
                if let seconds = state.pausedSeconds {
                    let duration = max(1, state.endsAt.timeIntervalSince(state.countdownStart))
                    ProgressView(value: min(1, max(0, Double(seconds) / duration)))
                } else {
                    ProgressView(timerInterval: state.countdownStart...state.endsAt, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                }
            }
            .progressViewStyle(.circular)
            .tint(accent)
            focusMark(state, size: size * 0.46)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func focusMark(_ state: FocusActivityAttributes.ContentState, size: CGFloat) -> some View {
        LineaFocusMark()
            .frame(width: size, height: size)
            .foregroundStyle(accent)
            .opacity(state.pausedSeconds == nil ? 1 : 0.6)
            .accessibilityLabel(state.pausedSeconds == nil ? "Таймер Linea" : "Таймер на паузе")
    }

    private func controls(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let paused = context.state.pausedSeconds != nil
        return HStack(spacing: 8) {
            Button(intent: FocusActivityIntent(paused ? .resume : .pause, for: context.attributes)) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(accent, in: Circle())
            }
            .accessibilityLabel(paused ? "Продолжить" : "Пауза")
            Button(intent: FocusActivityIntent(.finish, for: context.attributes)) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(accent)
                    .background(accent.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("Завершить")
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

private struct FocusTimerReadout<Content: View>: View {
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = 42
    let content: Content

    var body: some View {
        content
            .font(.system(size: fontSize, weight: .light, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A continuous line between two points, drawn for Linea at widget and island sizes.
private struct LineaFocusMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: side * 0.78, y: side * 0.16))
                    path.addCurve(
                        to: CGPoint(x: side * 0.22, y: side * 0.44),
                        control1: CGPoint(x: side * 0.78, y: side * 0.43),
                        control2: CGPoint(x: side * 0.22, y: side * 0.20)
                    )
                    path.addCurve(
                        to: CGPoint(x: side * 0.78, y: side * 0.62),
                        control1: CGPoint(x: side * 0.22, y: side * 0.67),
                        control2: CGPoint(x: side * 0.78, y: side * 0.39)
                    )
                    path.addCurve(
                        to: CGPoint(x: side * 0.22, y: side * 0.84),
                        control1: CGPoint(x: side * 0.78, y: side * 0.84),
                        control2: CGPoint(x: side * 0.40, y: side * 0.64)
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: side * 0.12, lineCap: .round, lineJoin: .round))
                Circle().frame(width: side * 0.24, height: side * 0.24)
                    .position(x: side * 0.78, y: side * 0.16)
                Circle().frame(width: side * 0.24, height: side * 0.24)
                    .position(x: side * 0.22, y: side * 0.84)
            }
        }
    }
}
