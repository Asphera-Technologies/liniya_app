//
//  LineaListRow.swift
//  Linea
//
//  The standard Linea list row: a title on the left, an optional quiet value
//  and a chevron on the right. Rows are composed into hairline-separated
//  lists via `LineaRowList`.
//

import SwiftUI

struct LineaListRow: View {
    let title: String
    var value: String? = nil
    var showsChevron: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(LineaFont.rowTitle)
                    .foregroundStyle(LineaColor.textPrimary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(LineaFont.rowValue)
                        .foregroundStyle(LineaColor.textTertiary)
                        .multilineTextAlignment(.trailing)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LineaColor.textTertiary)
                }
            }
            .padding(.vertical, LineaMetrics.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A model for a single row in a `LineaRowList`.
struct LineaRow: Identifiable {
    let id = UUID()
    let title: String
    var value: String? = nil
    var showsChevron: Bool = true
}

/// A vertical list of `LineaListRow`s separated by hairlines.
struct LineaRowList: View {
    let rows: [LineaRow]
    var onSelect: (LineaRow) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                LineaListRow(
                    title: row.title,
                    value: row.value,
                    showsChevron: row.showsChevron
                ) {
                    onSelect(row)
                }
                if index < rows.count - 1 {
                    LineaHairline()
                }
            }
        }
    }
}
