//
//  CommandBar.swift
//  Linea
//
//  The persistent "Что тебе нужно?" command bar pinned above the tab bar on
//  every screen. It is Linea's ambient AI entry point — tapping it opens the
//  Linea AI surface rather than navigating to a dedicated tab.
//

import SwiftUI

struct CommandBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.openAI()
        } label: {
            HStack {
                Text("Что тебе нужно?")
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: LineaMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                    .fill(LineaColor.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LineaMetrics.surfaceRadius, style: .continuous)
                    .strokeBorder(LineaColor.separator, lineWidth: LineaMetrics.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Спросить Linea")
        .accessibilityHint("Открывает Linea AI")
        .padding(.horizontal, LineaMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(LineaColor.background)
    }
}
