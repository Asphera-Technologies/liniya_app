import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(context.state.title).font(.headline).lineLimit(2)
                    Spacer()
                    countdown(context.state).font(.title2)
                }
                nextEvent(context.state)
                controls(context)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title).font(.headline).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    nextEvent(context.state)
                    controls(context)
                }
            } compactLeading: {
                Image(systemName: context.state.pausedSeconds == nil ? "timer" : "pause.fill")
            } compactTrailing: {
                countdown(context.state).font(.caption2).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.pausedSeconds == nil ? "timer" : "pause.fill")
            }
        }
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
        .minimumScaleFactor(0.7)
        .accessibilityLabel("Осталось")
    }

    private func nextEvent(_ state: FocusActivityAttributes.ContentState) -> some View {
        ViewThatFits {
            HStack {
                Text(state.nextEvent.map { "Дальше: \($0)" } ?? "Нет ближайших встреч")
                if let start = state.nextEventStart { Text(start, style: .time) }
            }
            Text(state.nextEvent.map { "Дальше: \($0)" } ?? "Нет ближайших встреч").lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func controls(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let paused = context.state.pausedSeconds != nil
        return HStack {
            Button(intent: FocusActivityIntent(paused ? .resume : .pause, for: context.attributes)) {
                Label(paused ? "Продолжить" : "Пауза", systemImage: paused ? "play.fill" : "pause.fill")
            }
            Button(intent: FocusActivityIntent(.finish, for: context.attributes)) {
                Label("Завершить", systemImage: "checkmark")
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }
}
