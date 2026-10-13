//
//  FocusView.swift
//  Linea
//
//  Минимальный фокус после «Начать» (ADR-041) — не помодоро, не музыка и не
//  статистика концентрации, а один спокойный экран:
//
//      Подготовить презентацию
//      ~45 мин
//      Начато в 11:20
//      [Завершить]
//      Не получается продолжить
//
//  Таймера нет: дело в работе, пока у задачи есть время начала, поэтому из
//  приложения можно выйти — выполнение продолжается. «Свернуть» оставляет
//  дело в работе; на «Сегодня» у него есть «Развернуть». Тексты — из ядра
//  (`TaskFocus`), действия — через `IntelligenceStore`, как везде.
//
//  Показывается поверх вкладок (`RootView`), а не листом: так он не спорит с
//  листами, открытыми в этот момент, — например, с карточкой задачи, где
//  нажали «Начать».
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
