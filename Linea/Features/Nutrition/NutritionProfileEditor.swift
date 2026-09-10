//
//  NutritionProfileEditor.swift
//  Linea
//
//  Editing the nutrition profile: diet, restrictions, products that do and do
//  not suit the user, health tags and meal times. Lists are edited as simple
//  chips — Linea has no product catalogue and does not need one to be useful.
//
//  Conditions are stored as plain user tags and are never interpreted: Linea
//  only filters suggestions by them and says so on the screen.
//

import SwiftUI

struct NutritionProfileEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: NutritionProfile
    @State private var newItem: [ListField: String] = [:]
    let onSave: (NutritionProfile) -> Void

    enum ListField: Hashable {
        case restrictions, excluded, preferred, conditions
    }

    init(profile: NutritionProfile, onSave: @escaping (NutritionProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Диета")
                        LineaTextField(
                            placeholder: "Например, средиземноморская",
                            text: Binding(get: { draft.dietType ?? "" }, set: { draft.dietType = $0.isEmpty ? nil : $0 })
                        )
                    }

                    listEditor("Ограничения", hint: "глютен, лактоза, сахар", field: .restrictions,
                               items: $draft.restrictions)
                    listEditor("Не подходит", hint: "продукты, которые лучше не есть", field: .excluded,
                               items: $draft.excludedProducts)
                    listEditor("Подходит", hint: "из этого Linea предложит еду", field: .preferred,
                               items: $draft.preferredProducts)
                    listEditor("Особенности здоровья", hint: "теги для фильтра, не диагноз", field: .conditions,
                               items: $draft.conditions)

                    mealWindowsSection
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Питание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.tint(LineaColor.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        onSave(draft)
                        dismiss()
                    }
                    .tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Lists

    private func listEditor(_ title: String, hint: String, field: ListField, items: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title, trailing: hint)
            if !items.wrappedValue.isEmpty {
                ChipsRow(items: items.wrappedValue) { item in
                    items.wrappedValue.removeAll { $0 == item }
                }
            }
            HStack(spacing: 10) {
                LineaTextField(
                    placeholder: "Добавить",
                    text: Binding(get: { newItem[field] ?? "" }, set: { newItem[field] = $0 })
                )
                Button {
                    add(field: field, into: items)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LineaColor.ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Добавить в «\(title)»")
            }
        }
    }

    private func add(field: ListField, into items: Binding<[String]>) {
        let value = (newItem[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !items.wrappedValue.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        items.wrappedValue.append(value)
        newItem[field] = ""
    }

    // MARK: Meal windows

    private var mealWindowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Время приёмов пищи", trailing: "занимают время в плане")
            VStack(spacing: 0) {
                ForEach(MealKind.allCases, id: \.self) { kind in
                    mealRow(kind)
                    if kind != MealKind.allCases.last { LineaHairline() }
                }
            }
        }
    }

    private func mealRow(_ kind: MealKind) -> some View {
        let index = draft.mealWindows.firstIndex { $0.kind == kind }
        return HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { index != nil },
                set: { isOn in
                    if isOn {
                        guard draft.mealWindows.allSatisfy({ $0.kind != kind }) else { return }
                        draft.mealWindows.append(MealWindow(kind: kind, start: Self.defaultStart(for: kind)))
                        draft.mealWindows.sort { $0.start < $1.start }
                    } else {
                        draft.mealWindows.removeAll { $0.kind == kind }
                    }
                }
            )) {
                Text(kind.title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
            }
            .tint(LineaColor.ink)

            if let index {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { Self.date(from: draft.mealWindows[index].start) },
                        set: { draft.mealWindows[index].start = Self.timeOfDay(from: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .tint(LineaColor.ink)
            }
        }
        .padding(.vertical, 10)
    }

    private static func defaultStart(for kind: MealKind) -> TimeOfDay {
        switch kind {
        case .breakfast: return TimeOfDay(hour: 8)
        case .lunch: return TimeOfDay(hour: 13)
        case .dinner: return TimeOfDay(hour: 19)
        case .snack: return TimeOfDay(hour: 16)
        }
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

/// A wrapping row of removable chips.
private struct ChipsRow: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onRemove(item)
                } label: {
                    HStack(spacing: 6) {
                        Text(item)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textPrimary)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous).fill(LineaColor.fill)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить \(item)")
            }
        }
    }
}

/// Minimal wrapping layout — chips of unpredictable width must not overflow.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = origin.y + lineHeight
        }
        return CGSize(width: proposal.width ?? origin.x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
