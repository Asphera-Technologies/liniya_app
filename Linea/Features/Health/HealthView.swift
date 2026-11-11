//
//  HealthView.swift
//  Linea
//
//  The Health screen: a grid of real Apple Health metrics, the sleep analysis
//  that the plan is actually built on, and today's workouts. No demo values:
//  each tile reflects its true state (loading / no data / value), and we never
//  fabricate a number when HealthKit returns nothing.
//
//  The sleep section is the point: one night deduplicated across sources, the
//  last week against this user's own norm, and an honest «собираю базу» while
//  there is not enough history to compare with.
//

import SwiftUI

struct HealthView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserProfileStore.self) private var profile
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(IntelligenceStore.self) private var intelligence
    @Environment(\.openURL) private var openURL

    @State private var didLoadProfile = false

    private let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .leading),
        GridItem(.flexible(), spacing: 20, alignment: .leading)
    ]

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Состояние", showsQuickAdd: true) {
                impactSection
                if healthEnabled {
                    metricsSection
                    connectSection
                    sleepSection
                    workoutsSection
                } else {
                    healthSetup("Apple Health отключен в Линии.")
                }
                NavigationLink {
                    NutritionView()
                        .navigationTitle("Питание")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Питание", systemImage: "fork.knife")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let entry = intelligence.todayCheckIn {
                    CheckInSummaryCard(numbers: DayDigestBuilder().numbers(for: entry.report)) {
                        appState.openCheckIn()
                    }
                } else {
                    LineaOutlineButton(title: "Итог дня") { appState.openCheckIn() }
                }
            }
        }
        .task {
            await profile.load()
            didLoadProfile = true
            await intelligence.refresh(reason: .appeared)
        }
        .task(id: shouldReadHealth) {
            guard didLoadProfile else { return }
            if shouldReadHealth { await healthKit.probeExistingAuthorization() }
        }
        .refreshable {
            if shouldReadHealth { await healthKit.refreshAll() }
            await intelligence.refresh(reason: .manual)
        }
    }

    private var healthEnabled: Bool { profile.profile.isHealthKitEnabled != false }
    private var shouldReadHealth: Bool { didLoadProfile && healthEnabled }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Влияние на план")
            Text(impactText)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !impactSources.isEmpty {
                Text("Учтены: \(impactSources.joined(separator: ", ")).")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius)
                .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("state.planImpact")
    }

    private var impactText: String {
        switch intelligence.planImpact {
        case nil:
            return "Влияние будет видно после расчета плана."
        case .noData:
            return healthEnabled
                ? "Пока мало данных о состоянии, поэтому показатели не меняют план."
                : "Apple Health отключен, данных о состоянии для изменения плана пока нет."
        case .unchanged:
            return "По доступным показателям время и объем задач в плане остались прежними."
        case .workload(let minutes, let difference):
            let change = difference < 0 ? "меньше" : "больше"
            return "С учетом состояния в плане \(minutes) мин задач. Это на \(abs(difference)) мин \(change), чем без учета показателей."
        case .placement(let title, let start):
            let clock = intelligence.time.timeOfDay(of: start)
            let formatted = String(format: "%d:%02d", clock.hour, clock.minute)
            return "С учетом состояния «\(title)» стоит в плане на \(formatted)."
        }
    }

    private var impactSources: [String] {
        guard didLoadProfile, let impact = intelligence.planImpact, impact != .noData else { return [] }
        return (intelligence.state?.components ?? []).compactMap { component in
            guard component.confidence > 0 else { return nil }
            switch component.kind {
            case .sleep where healthEnabled: return "сон"
            case .recovery where healthEnabled: return "восстановление"
            case .strain where healthEnabled: return "активность"
            case .fuel: return "питание"
            default: return nil
            }
        }
    }

    private func healthSetup(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LineaOutlineButton(title: "Открыть интеграции") { appState.openProfile() }
        }
    }

    // MARK: Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionLabel(text: "Сегодня", trailing: sourceTag)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                tile("Сон", healthKit.sleep, HealthFormat.sleep)
                tile("Шаги", healthKit.steps, HealthFormat.count)
                tile("Активность", healthKit.activeEnergy, HealthFormat.energy)
                tile("Дистанция", healthKit.distance, HealthFormat.distance)
                tile("Пульс покоя", healthKit.restingHeartRate, HealthFormat.count)
                tile("Пульс", healthKit.heartRate, HealthFormat.count)
                tile("HRV", healthKit.hrv, HealthFormat.milliseconds)
                tile("VO₂ Max", healthKit.vo2Max, HealthFormat.oneDecimal)
            }
        }
    }

    private func tile<T>(_ label: String, _ state: MetricState<T>, _ format: (T) -> String) -> some View {
        let display = display(state, format)
        return MetricTile(label: label, value: display.text, isPlaceholder: display.isPlaceholder)
    }

    /// Resolves a metric to display text, gated by the overall auth state so we
    /// never show a stale number before access is established.
    private func display<T>(_ state: MetricState<T>, _ format: (T) -> String) -> (text: String, isPlaceholder: Bool) {
        switch healthKit.authState {
        case .authorized:
            switch state {
            case .loading: return ("…", true)
            case .noData: return ("—", true)
            case .value(let v): return (format(v), false)
            }
        case .requesting:
            return ("…", true)
        case .notRequested, .failed, .unavailable:
            return ("—", true)
        }
    }

    private var sourceTag: String? {
        switch healthKit.authState {
        case .authorized: return "Apple Health"
        case .unavailable: return "Недоступно"
        default: return nil
        }
    }

    // MARK: Connect / errors

    @ViewBuilder
    private var connectSection: some View {
        switch healthKit.authState {
        case .notRequested where profile.profile.isHealthKitEnabled == true && !missingMetrics.isEmpty:
            partialAccessSection
        case .notRequested:
            healthSetup("Подключи Apple Health, чтобы видеть показатели и учитывать их в плане.")
        case .authorized where !missingMetrics.isEmpty:
            partialAccessSection
        case .failed:
            healthSetup("Не удалось прочитать данные Apple Health.")
        case .unavailable:
            Text("Apple Health недоступен на этом устройстве")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
        case .requesting, .authorized:
            EmptyView()
        }
    }

    /// Часть показателей пуста. Apple намеренно не сообщает, запрещено чтение
    /// или данных просто нет, поэтому Linea не гадает, а показывает, что
    /// именно не пришло, и ведёт туда, где это включается.
    ///
    /// Раньше этого экрана не было: как только приходил хотя бы один
    /// показатель, кнопка доступа пропадала, и включить остальные было негде.
    private var partialAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пока не вижу: \(missingMetrics.joined(separator: ", ")).")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Либо доступ к этим категориям выключен, либо данных нет. Проверить: «Здоровье» → фото профиля → «Приложения» → Linea.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 12) {
                LineaOutlineButton(title: "Открыть Здоровье") {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                }
                LineaOutlineButton(title: "Обновить") {
                    Task { await healthKit.refreshAll() }
                }
            }
        }
    }

    /// Названия показателей, по которым сегодня ничего не пришло.
    private var missingMetrics: [String] {
        var missing: [String] = []
        func check<T>(_ label: String, _ state: MetricState<T>) {
            if case .noData = state { missing.append(label) }
        }
        check("сон", healthKit.sleep)
        check("шаги", healthKit.steps)
        check("активность", healthKit.activeEnergy)
        check("пульс покоя", healthKit.restingHeartRate)
        check("HRV", healthKit.hrv)
        return missing
    }

    // MARK: Sleep analysis

    @ViewBuilder
    private var sleepSection: some View {
        let insight = intelligence.sleepInsight
        if !insight.recentNights.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Сон", trailing: sleepTag(insight))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    MetricTile(label: "За неделю", value: duration(insight.weekAverageSeconds))
                    MetricTile(
                        label: insight.canCompare ? "Обычно" : "Ориентир",
                        value: duration(insight.usualSeconds),
                        isPlaceholder: !insight.canCompare
                    )
                    MetricTile(label: "Эффективность", value: percent(insight.weekEfficiency))
                    MetricTile(label: "Отбой ±", value: minutes(insight.bedtimeStabilityMinutes))
                }
                SleepWeekChart(nights: insight.recentNights, usualSeconds: insight.usualSeconds)
                if let delta = insight.deltaSeconds, insight.canCompare {
                    Text(deltaText(delta))
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textSecondary)
                }
            }
        }
    }

    private func sleepTag(_ insight: SleepInsight) -> String? {
        guard let progress = insight.baselineProgress, !progress.isComplete else { return nil }
        return "база \(progress.days)/\(progress.needed)"
    }

    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        return HealthFormat.sleep(seconds)
    }

    private func percent(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    private func minutes(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) мин"
    }

    private func deltaText(_ delta: TimeInterval) -> String {
        let magnitude = HealthFormat.sleep(abs(delta))
        return delta < 0
            ? "За неделю на \(magnitude) меньше обычного."
            : "За неделю на \(magnitude) больше обычного."
    }

    // MARK: Workouts

    @ViewBuilder
    private var workoutsSection: some View {
        if case .authorized = healthKit.authState {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Тренировки")
                switch healthKit.workouts {
                case .value(let workouts):
                    VStack(spacing: 0) {
                        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                            workoutRow(workout)
                            if index < workouts.count - 1 { LineaHairline() }
                        }
                    }
                case .noData:
                    Text("Сегодня тренировок нет")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textTertiary)
                        .padding(.vertical, 14)
                case .loading:
                    Text("…")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textTertiary)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        HStack(spacing: 12) {
            Text(workout.activity)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer(minLength: 8)
            Text(HealthFormat.workoutDetail(workout))
                .font(LineaFont.rowValue)
                .foregroundStyle(LineaColor.textTertiary)
        }
        .padding(.vertical, 16)
    }
}

/// Compact, locale-aware formatting for health values (Russian style).
/// Members are `nonisolated` because they are pure functions passed around as
/// values (the project defaults declarations to the main actor).
enum HealthFormat {
    private nonisolated static let ru = Locale(identifier: "ru_RU")

    nonisolated static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(ru))
    }

    nonisolated static func sleep(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    nonisolated static func energy(_ kilocalories: Double) -> String {
        "\(Int(kilocalories.rounded())) ккал"
    }

    nonisolated static func distance(_ meters: Double) -> String {
        let km = meters / 1000
        return "\(km.formatted(.number.precision(.fractionLength(1)).locale(ru))) км"
    }

    nonisolated static func milliseconds(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    nonisolated static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(ru))
    }

    nonisolated static func workoutDetail(_ workout: WorkoutSummary) -> String {
        let minutes = Int((workout.duration / 60).rounded())
        var parts = ["\(minutes) мин"]
        if let energy = workout.energyKilocalories {
            parts.append("\(Int(energy.rounded())) ккал")
        }
        return parts.joined(separator: " · ")
    }
}
