//
//  LineaAIView.swift
//  Linea
//
//  The ambient Linea AI surface, presented as a sheet from the command bar.
//  Phase 1 is a faithful, calm shell: an intro from Linea, quick suggestions,
//  and a composer. Replies are LOCAL PLACEHOLDERS — there is no model wired in
//  yet. The real assistant channel plugs in via `LineaBackend` once the API
//  contract exists.
//

import SwiftUI

struct LineaAIView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var messages: [AIMessage] = []
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        greeting
                        if messages.isEmpty {
                            suggestions
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message).id(message.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LineaMetrics.screenPadding)
                    .padding(.vertical, 20)
                }
                .background(LineaColor.background.ignoresSafeArea())
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("Linea AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .tint(LineaColor.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if !appState.pendingPrompt.isEmpty {
                input = appState.pendingPrompt
                appState.pendingPrompt = ""
            }
        }
    }

    private var greeting: some View {
        Text(SampleData.aiGreeting)
            .font(LineaFont.feature)
            .foregroundStyle(LineaColor.textPrimary)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SampleData.aiSuggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LineaColor.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                            .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Что тебе нужно?", text: $input, axis: .vertical)
                .font(LineaFont.rowTitle)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(input) }
                .padding(.horizontal, 16)
                .frame(minHeight: LineaMetrics.controlHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                        .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
                )

            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LineaColor.onInk)
                    .frame(width: LineaMetrics.controlHeight, height: LineaMetrics.controlHeight)
                    .background(Circle().fill(LineaColor.ink))
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(LineaColor.background)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(AIMessage(role: .user, text: trimmed))
        input = ""
        inputFocused = false
        // Placeholder reply — no model connected in Phase 1.
        messages.append(AIMessage(
            role: .assistant,
            text: "Пока я в демо-режиме: ассистент подключится, когда будет готов бэкенд. Твой запрос сохранён."
        ))
    }
}

struct AIMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

private struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(LineaFont.rowTitle)
                .foregroundStyle(message.role == .user ? LineaColor.onInk : LineaColor.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                        .fill(message.role == .user ? LineaColor.ink : LineaColor.fill)
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    LineaAIView()
        .environment(AppState())
}
