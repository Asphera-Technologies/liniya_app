//
//  LineaScaffold.swift
//  Linea
//
//  The shared screen skeleton used by every top-level Linea screen:
//  the "Linea" wordmark, a large calm title (with optional trailing accessory),
//  and scrolling content.
//

import SwiftUI

struct LineaScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var titleTrailing: String? = nil
    var headerActions: AnyView? = nil
    var showsQuickAdd = false
    @ViewBuilder var content: () -> Content

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: LineaMetrics.headerSpacing) {
                    if !showsQuickAdd { wordmarkRow }
                    heading
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LineaMetrics.screenPadding)
            .padding(.top, showsQuickAdd ? LineaMetrics.headerSpacing : 12)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsQuickAdd {
                wordmarkRow
                    .padding(.horizontal, LineaMetrics.screenPadding)
                    .padding(.top, 12)
                    .background(LineaColor.background)
            }
        }
        .background(LineaColor.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var wordmarkRow: some View {
        HStack(spacing: 4) {
            Text("Linea")
                .font(LineaFont.wordmark)
                .foregroundStyle(LineaColor.textPrimary)
            Spacer(minLength: 8)
            if showsQuickAdd {
                Button {
                    appState.openQuickAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LineaColor.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(LineaColor.fill, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Новая задача")
            }
            headerActions
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subtitle {
                Text(subtitle)
                    .font(LineaFont.sectionLabel)
                    .foregroundStyle(LineaColor.textSecondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(LineaFont.largeTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                if let titleTrailing {
                    Spacer(minLength: 12)
                    Text(titleTrailing)
                        .font(LineaFont.sectionLabel)
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
        }
    }
}
