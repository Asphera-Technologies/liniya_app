//
//  DiagnosticsView.swift
//  Linea
//
//  Экран, ради которого заведён журнал: тестировщик ловит проблему днём, вдали
//  от компьютера, и одним касанием отправляет то, что приложение записало о
//  себе. Без него единственным способом понять причину был пересказ.
//

import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    private let reader = DiagnosticsReader()

    @State private var entries: [DiagnosticsReader.Entry] = []
    @State private var failure: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                    header
                    if isLoading {
                        Text("Читаю журнал…")
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textTertiary)
                    } else if let failure {
                        Text(failure)
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if entries.isEmpty {
                        Text("Записей пока нет. Открой экран, на котором проблема, вернись сюда и обнови.")
                            .font(LineaFont.caption)
                            .foregroundStyle(LineaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        log
                    }
                }
                .padding(.horizontal, LineaMetrics.screenPadding)
                .padding(.vertical, 20)
            }
            .background(LineaColor.background.ignoresSafeArea())
            .navigationTitle("Диагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }.tint(LineaColor.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: reader.report()) {
                        Text("Отправить")
                    }
                    .tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LineaLog.environment())
                .font(LineaFont.rowTitle)
                .foregroundStyle(LineaColor.textPrimary)
            Text("Здесь то, что приложение записало о себе за последний час. Кнопка «Отправить» отдаёт этот текст целиком.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            LineaOutlineButton(title: "Обновить") {
                Task { await load() }
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Журнал", trailing: "\(entries.count)")
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.time(entry.date)) · \(entry.category)")
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                    Text(entry.message)
                        .font(LineaFont.caption)
                        .foregroundStyle(isProblem(entry) ? .red : LineaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                LineaHairline()
            }
        }
    }

    private func isProblem(_ entry: DiagnosticsReader.Entry) -> Bool {
        entry.level == "ошибка" || entry.level == "сбой"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try reader.recentEntries()
            failure = nil
        } catch {
            failure = "Журнал прочитать не удалось: \(error.localizedDescription)"
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
