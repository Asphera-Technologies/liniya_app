//
//  CheckInView.swift
//  Linea
//
//  Экран «Итог дня»: рассказать голосом до пяти минут или написать, дождаться
//  разбора, проверить галочки и сохранить. Экран только показывает фазы
//  `CheckInStore` — решения принимают стор и ядро.
//

import SwiftUI

struct CheckInView: View {
    @Environment(CheckInStore.self) private var store
    @Environment(LocalSpeechModel.self) private var localModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    if let notice = store.notice, store.phase != .recording {
                        Text(notice)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LineaColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle("Итог дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.phase == .saved ? "Готово" : "Закрыть") { close() }
                        .tint(LineaColor.ink)
                        .disabled(store.phase == .saving)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.phase == .recording || store.phase == .saving)
        .task { await store.begin() }
        // Лист уехал — экран сбрасывается. Не раньше: иначе во время анимации
        // закрытия мелькнул бы начальный экран.
        .onDisappear { store.end() }
    }

    private func close() {
        // Микрофон и начатая работа гаснут сразу, не дожидаясь анимации.
        store.stopWork()
        dismiss()
    }

    // MARK: Фазы

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .start:
            startSection
        case .recording:
            recordingSection
        case .transcribing:
            waiting("Распознаю рассказ…", detail: transcribingDetail)
        case .writing:
            writingSection
        case .analyzing:
            waiting("Разбираю, что сделано…", detail: nil)
        case .review:
            reviewSection
        case .saving:
            waiting("Сохраняю…", detail: nil)
        case .saved:
            savedSection
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Расскажи, как прошёл день: что получилось, что осталось, сколько было работы и как самочувствие.")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 14) {
                Button {
                    store.startRecording()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(LineaColor.onInk)
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(LineaColor.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Рассказать голосом")

                Text("До пяти минут")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
            }
            .frame(maxWidth: .infinity)

            LineaOutlineButton(title: "Написать текстом") { store.switchToText() }
                .frame(maxWidth: .infinity)

            if let error = store.errorMessage {
                errorText(error)
            }
            if store.hasSavedEntry {
                caption("Итог за этот день уже есть — новый рассказ его заменит.")
            }
            caption(privacyText)
            if !localModel.isReady {
                LocalModelRow()
            }
        }
    }

    private var privacyText: String {
        if localModel.isReady {
            return "Всё происходит на телефоне: голос распознаёт модель, рассказ разбирают правила. Запись и текст никуда не уходят."
        }
        return "Голос распознаёт системная диктовка iPhone — точность невысокая. Точнее — с моделью на телефоне. Запись и текст никуда не уходят."
    }

    private var transcribingDetail: String {
        if localModel.isReady { return "Модель на телефоне, без сети. Обычно меньше минуты." }
        return "Системная диктовка, без сети. Первый раз iOS загружает свою модель распознавания."
    }

    private var recordingSection: some View {
        VStack(spacing: 24) {
            Text(clock(store.recorder.elapsed) + " / " + clock(VoiceRecorder.maxDuration))
                .font(LineaFont.metricValue)
                .monospacedDigit()
                .foregroundStyle(LineaColor.textPrimary)

            LevelMeter(level: store.recorder.level)
                .frame(height: 40)

            Button {
                store.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LineaColor.onInk)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(LineaColor.ink))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закончить рассказ")

            if VoiceRecorder.maxDuration - store.recorder.elapsed < 30 {
                caption("Осталось меньше тридцати секунд.")
            }

            Button("Отменить запись") { store.cancelRecording() }
                .font(LineaFont.control)
                .tint(LineaColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var writingSection: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Рассказ", trailing: store.hasSavedEntry ? "заменит сохранённый" : nil)
            ZStack(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("Сегодня получилось… Осталось… Работы было примерно… Самочувствие…")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.text)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .frame(minHeight: 220)
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                    .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
            )

            if let error = store.errorMessage {
                errorText(error)
            }
            caption("Можно диктовать с клавиатуры — кнопка микрофона внизу.")
            Button("Рассказать голосом") {
                isEditorFocused = false
                store.startRecording()
            }
            .font(LineaFont.control)
            .tint(LineaColor.textSecondary)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let current = store.draft {
            CheckInReviewView(
                draft: draftBinding(fallback: current),
                moving: store.movingTitles,
                onEditStory: { store.editStory() }
            )
        }
    }

    /// Не `Binding($store.draft)`: такая привязка падает, если черновик
    /// обнулился, пока экран проверки ещё на экране, — так вылетало повторное
    /// открытие итога дня. Здесь до ухода экрана он видит последний черновик.
    private func draftBinding(fallback: CheckInDraft) -> Binding<CheckInDraft> {
        Binding(
            get: { store.draft ?? fallback },
            set: { value in
                guard store.draft != nil else { return }
                store.draft = value
            }
        )
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Итог сохранён")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            if let entry = store.savedEntry {
                Text(entry.digest)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            caption("План на завтра учтёт, сколько получилось сегодня. Всё, что сохранено в памяти, — в «Профиль» → «Память».")
        }
    }

    // MARK: Нижняя панель

    @ViewBuilder
    private var bottomBar: some View {
        switch store.phase {
        case .writing:
            primaryButton("Разобрать", disabled: store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                isEditorFocused = false
                store.analyze()
            }
        case .review:
            primaryButton("Сохранить итог", disabled: false) {
                store.save()
            }
        default:
            EmptyView()
        }
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LineaFont.control)
                .foregroundStyle(LineaColor.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: LineaMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                        .fill(LineaColor.ink)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.vertical, 10)
        .background(LineaColor.background)
    }

    // MARK: Мелочи

    private func waiting(_ title: String, detail: String?) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(LineaColor.ink)
            Text(title)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            if let detail {
                caption(detail)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LineaFont.caption)
            .foregroundStyle(LineaColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(LineaFont.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Полоски громкости: видно, что микрофон слышит.
private struct LevelMeter: View {
    let level: Double
    private let bars = 24

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars, id: \.self) { index in
                let distance = abs(Double(index) - Double(bars - 1) / 2) / (Double(bars) / 2)
                let height = max(0.08, level * (1 - distance * 0.7))
                Capsule()
                    .fill(LineaColor.ink.opacity(0.75))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(x: 1, y: height, anchor: .center)
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
