//
//  ProfileView.swift
//  Linea
//
import SwiftUI
import EventKit

struct ProfileView: View {
    @Environment(UserProfileStore.self) private var profile
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(MemoryStore.self) private var memory
    @Environment(\.dismiss) private var dismiss

    @State private var eventStore = EKEventStore()
    @State private var isEditingProfile = false
    @State private var isShowingMemory = false
    @State private var isChangingConnection = false
    @State private var calendarDenied = false
    @State private var healthFailed = false

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Профиль") {
                aboutSection
                connectionsSection
                intelligenceSection
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task {
            await profile.load()
            if profile.profile.isHealthKitEnabled != false {
                await healthKit.probeExistingAuthorization()
            }
            await memory.loadIfNeeded()
        }
        .sheet(isPresented: $isEditingProfile) {
            AboutMeEditor(profile: profile.profile) { updated in
                Task { await profile.save(updated) }
            }
        }
        .sheet(isPresented: $isShowingMemory) { MemoryView() }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "О себе")
            LineaListRow(title: "Имя", value: profile.profile.name ?? "Не задано") { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Рабочий день", value: workdayText) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Тихие часы", value: quietText) { isEditingProfile = true }
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

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Интеграции")
            Toggle(isOn: Binding(
                get: { profile.profile.isHealthKitEnabled ?? healthKit.isAuthorized },
                set: { enabled in Task { await setHealth(enabled: enabled) } }
            )) {
                connectionLabel("Apple Health", "Показатели здоровья помогают подстроить план")
            }
            .accessibilityIdentifier("profile.healthKit")
            if healthFailed {
                connectionHint("Не удалось подключить Apple Health. Проверь доступ в приложении «Здоровье».")
            }
            LineaHairline()
            Toggle(isOn: Binding(
                get: { profile.profile.isCalendarEnabled },
                set: { enabled in Task { await setCalendar(enabled: enabled) } }
            )) {
                connectionLabel("Календарь", "События займут время в плане дня")
            }
            .accessibilityIdentifier("profile.calendar")
            if calendarDenied || (profile.profile.isCalendarEnabled && !CalendarAccess.isAuthorized) {
                connectionHint("Разреши доступ к календарю в настройках iOS.")
            }
            if profile.errorMessage != nil {
                connectionHint("Не удалось сохранить настройки. Попробуй еще раз.")
            }
        }
        .tint(LineaColor.ink)
        .disabled(isChangingConnection)
    }

    private func connectionLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LineaFont.rowTitle).foregroundStyle(LineaColor.textPrimary)
            Text(detail).font(LineaFont.caption).foregroundStyle(LineaColor.textTertiary)
        }
        .padding(.vertical, 10)
    }

    private func connectionHint(_ text: String) -> some View {
        Text(text).font(LineaFont.caption).foregroundStyle(LineaColor.textSecondary)
    }

    private func setHealth(enabled: Bool) async {
        guard !isChangingConnection else { return }
        isChangingConnection = true
        defer { isChangingConnection = false }
        if enabled { await healthKit.connect() }
        let connected = enabled && healthKit.isAuthorized
        healthFailed = enabled && !connected
        var updated = profile.profile
        updated.isHealthKitEnabled = connected
        await profile.save(updated)
    }

    private func setCalendar(enabled: Bool) async {
        guard !isChangingConnection else { return }
        isChangingConnection = true
        defer { isChangingConnection = false }
        let granted = enabled ? await CalendarAccess.request(eventStore) : false
        calendarDenied = enabled && !granted
        var updated = profile.profile
        updated.isCalendarEnabled = granted
        await profile.save(updated)
    }

    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Линия AI")
            assistantRow
            LineaHairline()
            LineaListRow(title: "Память", value: memoryText) { isShowingMemory = true }
        }
        .disabled(isChangingConnection)
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
                    Text("Вопросы, краткий контекст дня и выжимка из памяти отправляются для ответа через интернет")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
            .tint(LineaColor.ink)
            .disabled(!AISettings.isConfigured)
            .padding(.vertical, 10)

            if !AISettings.isConfigured {
                Text("Свободный разговор сейчас недоступен.")
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

}
