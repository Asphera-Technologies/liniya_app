//
//  FocusView.swift
//  Linea
//
import SwiftUI

struct FocusView: View {
    let focus: TaskFocus

    @Environment(IntelligenceStore.self) private var intelligence
    /// «Завершить» и «Не получается продолжить» срабатывают один раз.
    @State private var isActing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    intelligence.minimizeFocus()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(LineaColor.textSecondary)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Свернуть")
                .accessibilityIdentifier("focus.minimize")
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "В работе")
                    Text(focus.title)
                        .font(LineaFont.largeTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("focus.title")

                    ZStack {
                        Circle()
                            .strokeBorder(LineaColor.textTertiary.opacity(0.25), lineWidth: 4)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let fraction = Double(focus.remainingSeconds(at: context.date)) / Double(focus.minutes * 60)
                            Circle()
                                .trim(from: 0, to: min(1, fraction))
                                .stroke(LineaColor.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .accessibilityHidden(true)
                        }
                        VStack(spacing: 4) {
                            FocusCountdown(focus: focus)
                                .font(.system(size: 64, weight: .light, design: .rounded))
                                .minimumScaleFactor(0.5)
                            if focus.isPaused {
                                Text("На паузе").font(LineaFont.caption).foregroundStyle(LineaColor.textSecondary)
                            }
                        }
                        .padding(18)
                    }
                    .frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.duration)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textSecondary)
                        Text(focus.started)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textSecondary)
                            .accessibilityIdentifier("focus.started")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 18) {
                LineaPrimaryButton(title: "Завершить", fillsWidth: true) {
                    act(.finish)
                }
                .accessibilityIdentifier("focus.finish")
                Button(focus.isPaused ? "Продолжить" : "Пауза") {
                    Task { await intelligence.setFocusPaused(!focus.isPaused, taskID: focus.taskID, startedAt: focus.startedAt) }
                }
                .font(LineaFont.control)
                .accessibilityIdentifier("focus.pauseResume")
                Button(TaskFocus.stopTitle) {
                    act(.stop)
                }
                .font(LineaFont.control)
                .foregroundStyle(LineaColor.textSecondary)
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus.stop")
                Text(TaskFocus.hint)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(isActing)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LineaColor.background.ignoresSafeArea())
        // Пока фокус открыт, VoiceOver не читает вкладки под ним.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("focus")
    }

    private enum Step { case finish, stop }

    private func act(_ step: Step) {
        guard !isActing else { return }
        isActing = true
        Task {
            switch step {
            case .finish: await intelligence.finishFocus()
            case .stop: await intelligence.stopFocus()
            }
            isActing = false
        }
    }
}


struct FocusCountdown: View {
    let focus: TaskFocus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = focus.remainingSeconds(at: context.date)
            Text(Duration.seconds(seconds).formatted(
                .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2))
            ))
            .monospacedDigit()
            .accessibilityLabel(focus.isPaused ? "Пауза, осталось" : "Осталось")
            .accessibilityValue(Duration.seconds(seconds).formatted(.units(width: .wide)))
            .accessibilityIdentifier("focus.countdown")
        }
    }
}
