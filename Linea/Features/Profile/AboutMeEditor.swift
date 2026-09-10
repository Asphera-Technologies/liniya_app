//
//  AboutMeEditor.swift
//  Linea
//
//  «О себе»: the working day, quiet hours, the evening check-in time and the
//  target sleep. Linea plans inside the working day, never nudges during quiet
//  hours, and uses the sleep target until it has learned the user's own norm.
//

import SwiftUI

struct AboutMeEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Имя")
                        LineaTextField(
                            placeholder: "Как к тебе обращаться",
                            text: Binding(get: { draft.name ?? "" }, set: { draft.name = $0.isEmpty ? nil : $0 })
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Рабочий день", trailing: "в этих границах строится план")
                        timeRow("Начало", time: $draft.workdayStart)
                        LineaHairline()
                        timeRow("Конец", time: $draft.workdayEnd)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Тихие часы", trailing: "Linea молчит")
                        timeRow("С", time: $draft.quietHoursStart)
                        LineaHairline()
                        timeRow("До", time: $draft.quietHoursEnd)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Вечерний вопрос")
                        timeRow("Спрашивать в", time: $draft.eveningCheckIn)
                    }

                    sleepNeedSection
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("О себе")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        var result = draft
                        result.onboardingCompleted = true
                        onSave(result)
                        dismiss()
                    }
                    .tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var sleepNeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Сколько сна тебе нужно", trailing: hoursText(draft.sleepNeedSeconds))
            Slider(
                value: Binding(
                    get: { draft.sleepNeedSeconds / 3600 },
                    set: { draft.sleepNeedSeconds = $0 * 3600 }
                ),
                in: 5...10,
                step: 0.25
            )
            .tint(LineaColor.ink)
            Text("Используется, пока Linea не собрала твою личную норму.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
        }
    }

    private func timeRow(_ title: String, time: Binding<TimeOfDay>) -> some View {
        HStack {
            Text(title)
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer(minLength: 8)
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.date(from: time.wrappedValue) },
                    set: { time.wrappedValue = Self.timeOfDay(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .tint(LineaColor.ink)
        }
        .padding(.vertical, 10)
    }

    private func hoursText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    private static func date(from time: TimeOfDay) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: DateComponents(hour: time.hour, minute: time.minute), to: start) ?? start
    }

    private static func timeOfDay(from date: Date) -> TimeOfDay {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}
