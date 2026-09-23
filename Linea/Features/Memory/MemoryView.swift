//
//  MemoryView.swift
//  Linea
//
//  «Память»: что Linea знает о человеке и дневник итогов дня. Всё видно и
//  всё удаляется — память, которую нельзя посмотреть, не вызывает доверия.
//  Отсюда же можно рассказать итог дня в любое время, не дожидаясь вечера.
//

import SwiftUI

struct MemoryView: View {
    @Environment(MemoryStore.self) private var memory
    @Environment(\.dismiss) private var dismiss

    @State private var newFact = ""
    @State private var selectedEntry: CheckInEntry?
    @State private var isShowingCheckIn = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    Text("Linea запоминает то, что пригодится потом: привычки, ограничения, закономерности — и коротко каждый день из итога. Хранится только на телефоне. В модель уходит не весь дневник, а выжимка.")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LineaOutlineButton(title: "Рассказать итог дня") { isShowingCheckIn = true }

                    factsSection
                    journalSection

                    if let error = memory.errorMessage {
                        Text(error)
                            .font(LineaFont.caption)
                            .foregroundStyle(.red)
                    }

                    if !memory.memory.facts.isEmpty || !memory.entries.isEmpty {
                        Button(role: .destructive) {
                            isConfirmingDeleteAll = true
                        } label: {
                            Text("Стереть всю память")
                                .font(LineaFont.control)
                                .foregroundStyle(.red)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Память")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await memory.load() }
        .sheet(item: $selectedEntry) { entry in
            CheckInEntryView(entry: entry, title: DayDigestBuilder.dayLabel(entry.day, time: memory.time)) {
                Task { await memory.deleteEntry(entry) }
                selectedEntry = nil
            }
        }
        .sheet(isPresented: $isShowingCheckIn, onDismiss: { Task { await memory.load() } }) {
            CheckInView()
        }
        .confirmationDialog("Стереть всё, что Linea помнит?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Стереть факты и дневник", role: .destructive) {
                Task { await memory.deleteAll() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Задачи, план и калибровка останутся.")
        }
    }

    // MARK: Факты

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Что Linea знает о тебе", trailing: memory.memory.facts.isEmpty ? nil : "\(memory.memory.facts.count)")
            if memory.memory.facts.isEmpty {
                Text("Пока ничего. Факты появятся из итогов дня — или скажи в чате «запомни, что…».")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
            ForEach(sortedFacts) { fact in
                FactRow(fact: fact, sourceText: sourceText(fact)) {
                    Task { await memory.deleteFact(fact) }
                }
                LineaHairline()
            }
            HStack(alignment: .bottom, spacing: 12) {
                LineaTextField(placeholder: "Записать самому", text: $newFact, axis: .vertical)
                Button("Добавить") {
                    let text = newFact
                    newFact = ""
                    Task { await memory.addFact(text) }
                }
                .font(LineaFont.control)
                .tint(LineaColor.ink)
                .disabled(newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
    }

    private var sortedFacts: [MemoryFact] {
        memory.memory.facts.sorted { lhs, rhs in
            lhs.lastConfirmedAt != rhs.lastConfirmedAt ? lhs.lastConfirmedAt > rhs.lastConfirmedAt : lhs.createdAt > rhs.createdAt
        }
    }

    private func sourceText(_ fact: MemoryFact) -> String {
        var parts: [String] = [fact.kind.title.lowercased()]
        switch fact.source {
        case .checkIn(let day): parts.append("из итога \(DayDigestBuilder.dayLabel(day, time: memory.time))")
        case .chat: parts.append("из разговора")
        case .manual: parts.append("записано вручную")
        }
        if fact.confirmations > 1 {
            parts.append("звучало \(fact.confirmations) \(RussianText.plural(fact.confirmations, "раз", "раза", "раз"))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Дневник

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Итоги дней", trailing: memory.entries.isEmpty ? nil : "\(memory.entries.count)")
            if memory.entries.isEmpty {
                Text("Итогов ещё нет. Вечером на экране «Сегодня» появится вопрос «Как прошёл день?».")
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
            ForEach(memory.entries.prefix(30)) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(DayDigestBuilder().headline(for: entry.report, day: entry.day, time: memory.time))
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                LineaHairline()
            }
        }
    }
}

private struct FactRow: View {
    let fact: MemoryFact
    let sourceText: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.text)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceText)
                    .font(LineaFont.caption)
                    .foregroundStyle(LineaColor.textTertiary)
            }
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LineaColor.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Забыть")
        }
        .padding(.vertical, 10)
    }
}

/// Один день дневника: выжимка, рассказ, если ещё хранится, и удаление.
struct CheckInEntryView: View {
    let entry: CheckInEntry
    /// «22.09, пн».
    let title: String
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    Text(entry.digest)
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Рассказ", trailing: entry.source.isVoice ? "голосом" : "текстом")
                        Text(entry.transcript ?? "Сам рассказ старше \(CheckInEntry.compactionDays) дней и уже стёрт — осталась выжимка.")
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(entry.transcript == nil ? LineaColor.textTertiary : LineaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("Удалить этот день")
                            .font(LineaFont.control)
                            .foregroundStyle(.red)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
