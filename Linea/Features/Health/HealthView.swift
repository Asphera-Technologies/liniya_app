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
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(IntelligenceStore.self) private var intelligence

    private let columns = [
        GridItem(.flexible(), spacing: 20, alignment: .leading),
        GridItem(.flexible(), spacing: 20, alignment: .leading)
    ]

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Здоровье") {
                metricsSection
                connectSection
                sleepSection
                workoutsSection
            }
        }
        .task {
            await healthKit.probeExistingAuthorization()
            await intelligence.refresh(reason: .appeared)
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
        case .notRequested:
            VStack(alignment: .leading, spacing: 10) {
                Text("Подключи Apple Health, чтобы видеть свои реальные показатели.")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                LineaOutlineButton(title: "Подключить Apple Health") {
                    Task { await healthKit.connect() }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text("Не удалось прочитать данные Apple Health")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textSecondary)
                Text(message)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                LineaOutlineButton(title: "Повторить") {
                    Task { await healthKit.connect() }
                }
            }
        case .unavailable:
            Text("Apple Health недоступен на этом устройстве")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
        case .requesting, .authorized:
            EmptyView()
        }
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
