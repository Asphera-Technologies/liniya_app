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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LineaMetrics.headerSpacing) {
            HStack {
                Text("Linea")
                    .font(LineaFont.wordmark)
                    .foregroundStyle(LineaColor.textPrimary)
                if let headerActions {
                    Spacer()
                    headerActions
                }
            }

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
}
