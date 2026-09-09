//
//  LineaScaffold.swift
//  Linea
//
//  The shared screen skeleton used by every top-level Linea screen:
//  the "Linea" wordmark, a large calm title (with optional trailing accessory),
//  scrolling content, and the persistent command bar pinned at the bottom.
//

import SwiftUI

struct LineaScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var titleTrailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LineaMetrics.sectionSpacing) {
                header
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LineaMetrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(LineaColor.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CommandBar()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LineaMetrics.headerSpacing) {
            Text("Linea")
                .font(LineaFont.wordmark)
                .foregroundStyle(LineaColor.textPrimary)

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
        .accessibilityElement(children: .combine)
    }
}
