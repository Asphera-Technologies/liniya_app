//
//  ProfileView.swift
//  Linea
//
//  The Profile screen. Everything here is real: the working day that defines
//  available time, the state of every connector, which explainer writes the
//  texts, and what Linea has learned from the evening ratings — with a way to
//  reset it. Nothing is shown that Linea does not actually use.
//

import SwiftUI
import EventKit

struct ProfileView: View {
    @Environment(UserProfileStore.self) private var profile
    @Environment(PlanStore.self) private var plan
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(IntelligenceStore.self) private var intelligence
    @Environment(MemoryStore.self) private var memory

    /// Used only to ask for calendar access from this screen. Authorization is
    /// app-wide, so this may be a different instance from the connector's.
    @State private var eventStore = EKEventStore()

    @State private var isEditingProfile = false
    @State private var isShowingCalibration = false
    @State private var isShowingDiagnostics = false
    @State private var isShowingMemory = false
    @State private var calendarDenied = false

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Профиль") {
                aboutSection
                connectionsSection
                speechSection
                intelligenceSection
            }
        }
        .task {
            await profile.load()
            await memory.loadIfNeeded()
        }
        .sheet(isPresented: $isEditingProfile) {
            AboutMeEditor(profile: profile.profile) { updated in
                Task { await profile.save(updated) }
            }
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView()
        }
        .sheet(isPresented: $isShowingMemory) {
            MemoryView()
        }
        .sheet(isPresented: $isShowingCalibration) {
            CalibrationView(
                calibration: intelligence.calibration,
                onReset: { Task { await intelligence.resetCalibration() } }
            )
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "О себе")
            LineaListRow(title: "Имя", value: profile.profile.name ?? "Не задано") { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Рабочий день", value: workdayText) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Тихие часы", value: quietText) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Цели", value: "\(plan.activeGoals.count) активных", showsChevron: false)
        }
    }

    private var workdayText: String {
        "\(clock(profile.profile.workdayStart)) — \(clock(profile.profile.workdayEnd))"
    }

    private var quietText: String {
        "\(clock(profile.profile.quietHoursStart)) — \(clock(profile.profile.quietHoursEnd))"
    }

    private func clock(_ time: TimeOfDay) -> String {
        String(format: "%d:%02d", time.hour, time.minute)
    }

    // MARK: Connections

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Подключения", trailing: "источники данных")
            LineaListRow(title: "Apple Health", value: healthStatusText, showsChevron: false)
            ForEach(intelligence.connections, id: \.id) { connection in
                LineaHairline()
                LineaListRow(title: connection.title, value: connection.statusText, showsChevron: false)
            }
            LineaHairline()
            calendarRow
        }
    }

    /// The calendar is the second connector, and it is opt-in: the permission
    /// dialog belongs to a deliberate tap here, not to a background refresh.
    private var calendarRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { profile.profile.isCalendarEnabled },
                set: { isOn in Task { await setCalendar(enabled: isOn) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Календарь")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                    Text("События займут время в плане дня")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
            .tint(LineaColor.ink)
            .padding(.vertical, 10)

            if calendarDenied {
                Text("Доступ к календарю запрещён. Включить его можно в «Настройках» iOS.")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .padding(.bottom, 8)
            }
        }
    }

    private func setCalendar(enabled: Bool) async {
        var updated = profile.profile
        guard enabled else {
            calendarDenied = false
            updated.isCalendarEnabled = false
            await profile.save(updated)
            return
        }
        let granted = await CalendarAccess.request(eventStore)
        calendarDenied = !granted
        updated.isCalendarEnabled = granted
        await profile.save(updated)
    }

    private var healthStatusText: String {
        switch healthKit.authState {
        case .authorized: return "Подключено"
        case .requesting: return "Подключаем…"
        case .unavailable: return "Недоступно"
        case .failed: return "Ошибка доступа"
        case .notRequested: return "Не подключено"
        }
    }

    // MARK: Распознавание речи

    /// Модель на телефоне: итог дня распознаётся без сети, наружу не уходит ничего.
    private var speechSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Распознавание речи", trailing: "итог дня")
            LocalModelRow()
        }
    }

    // MARK: Intelligence

    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Linea AI")
            LineaListRow(title: "Модель", value: AISettings.statusText, showsChevron: false)
            LineaHairline()
            assistantRow
            LineaHairline()
            LineaListRow(title: "Память", value: memoryText) { isShowingMemory = true }
            LineaHairline()
            LineaListRow(title: "Тексты пишет", value: intelligence.explainerTitle, showsChevron: false)
            LineaHairline()
            LineaListRow(title: "Калибровка", value: calibrationText) { isShowingCalibration = true }
            LineaHairline()
            LineaListRow(title: "Диагностика", value: "Журнал приложения") { isShowingDiagnostics = true }
        }
    }

    /// Пока переключатель выключен, наружу не уходит ничего: тексты собирает
    /// само приложение. Включая его, пользователь соглашается отправлять
    /// производные факты о дне — не сами замеры из «Здоровья».
    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { profile.profile.isCloudAssistantEnabled },
                set: { isOn in
                    Task {
                        var updated = profile.profile
                        updated.isCloudAssistantEnabled = isOn
                        await profile.save(updated)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Свободный разговор")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                    Text("Вопросы уходят модели вместе с кратким контекстом дня и выжимкой из памяти")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
            .tint(LineaColor.ink)
            .disabled(!AISettings.isConfigured)
            .padding(.vertical, 10)

            if !AISettings.isConfigured {
                Text("Ключ доступа к модели не настроен — см. Docs/secrets.md.")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .padding(.bottom, 8)
            }
        }
    }

    private var memoryText: String {
        let facts = memory.memory.facts.count
        let days = memory.entries.count
        if facts == 0 && days == 0 { return "Пусто" }
        return "\(facts) \(RussianText.plural(facts, "факт", "факта", "фактов")), \(days) \(RussianText.plural(days, "день", "дня", "дней"))"
    }

    private var calibrationText: String {
        let count = intelligence.calibration.ratingsCount
        return count == 0 ? "Пока нет оценок" : "\(count) оценок дня"
    }
}

/// What Linea learned from the evening ratings, in plain words, plus a reset.
struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss

    let calibration: Calibration
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    Text("Linea подстраивается под тебя по вечерним оценкам. Порядок задач она не переучивает — меняются только эти настройки.")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Что подстроено")
                        row("Оценка сил", value: signed(calibration.energyBias))
                        LineaHairline()
                        row("Порог «снизить нагрузку»", value: percent(calibration.reduceThreshold))
                        LineaHairline()
                        row("Порог «можно больше»", value: percent(calibration.pushThreshold))
                        LineaHairline()
                        row("Ёмкость дня", value: percent(calibration.capacityFactor))
                        LineaHairline()
                        row("Запас на задачи", value: multiplier(calibration.estimateMultiplier))
                        LineaHairline()
                        row("Пауза перед напоминанием", value: "\(calibration.nudgeGraceMinutes) мин")
                    }

                    if !calibration.changeLog.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Что менялось")
                            ForEach(Array(calibration.changeLog.suffix(8).reversed().enumerated()), id: \.offset) { _, change in
                                Text(change.reason)
                                    .font(LineaFont.caption)
                                    .foregroundStyle(LineaColor.textTertiary)
                                    .padding(.vertical, 4)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        onReset()
                        dismiss()
                    } label: {
                        Text("Сбросить калибровку")
                            .font(LineaFont.control)
                            .foregroundStyle(.red)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Калибровка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, value: String) -> some View {
        LineaListRow(title: title, value: value, showsChevron: false)
    }

    private func signed(_ value: Double) -> String {
        value == 0 ? "по умолчанию" : String(format: "%+.2f", value)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func multiplier(_ value: Double) -> String {
        String(format: "×%.2f", value)
    }
}
