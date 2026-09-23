//
//  LocalModelRow.swift
//  Linea
//
//  Строка «Модель на телефоне»: скачать, дождаться, удалить. Одна и та же
//  в «Профиле» и на экране итога дня, чтобы модель можно было поставить
//  прямо перед рассказом.
//

import SwiftUI

struct LocalModelRow: View {
    @Environment(LocalSpeechModel.self) private var model
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Модель на телефоне")
                        .font(LineaFont.rowTitle)
                        .foregroundStyle(LineaColor.textPrimary)
                    Text(statusText)
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textTertiary)
                }
                Spacer(minLength: 8)
                action
            }

            if case .downloading(let progress) = model.state {
                ProgressView(value: progress)
                    .tint(LineaColor.ink)
            }
            if case .failed(let message) = model.state {
                Text(message)
                    .font(LineaFont.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.isReady
                 ? "Русская речь распознаётся прямо на телефоне, со знаками препинания. Голос никуда не уходит."
                 : "Распознаёт русскую речь прямо на телефоне, точнее системной диктовки. Голос никуда не уходит. Скачивается один раз — лучше по Wi-Fi.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .confirmationDialog("Удалить модель распознавания?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { model.delete() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Освободится \(GigaAMModel.sizeText). Голос будет распознавать системная диктовка или Grok, если он включён.")
        }
    }

    private var statusText: String {
        switch model.state {
        case .notInstalled: return "\(GigaAMModel.title) · \(GigaAMModel.sizeText)"
        case .downloading(let progress): return "Скачивается · \(Int((progress * 100).rounded())) %"
        case .verifying: return "Проверяю файлы…"
        case .ready: return "\(GigaAMModel.title) · готова"
        case .failed: return "Не скачалась"
        }
    }

    @ViewBuilder
    private var action: some View {
        switch model.state {
        case .notInstalled:
            Button("Скачать") { model.download() }
                .font(LineaFont.control)
                .tint(LineaColor.ink)
        case .downloading, .verifying:
            Button("Отменить") { model.cancel() }
                .font(LineaFont.control)
                .tint(LineaColor.textSecondary)
        case .ready:
            Button("Удалить") { isConfirmingDelete = true }
                .font(LineaFont.control)
                .tint(LineaColor.textSecondary)
        case .failed:
            Button("Повторить") { model.download() }
                .font(LineaFont.control)
                .tint(LineaColor.ink)
        }
    }
}
