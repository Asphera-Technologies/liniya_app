//
//  LineaSegmentedControl.swift
//  Linea
//
//  A calm two-plus segment control matching Linea's "Неделя / Месяц" toggle:
//  a light track with a solid ink pill behind the selected segment.
//

import SwiftUI

struct LineaSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let isSelected = index == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = index
                    }
                } label: {
                    Text(options[index])
                        .font(LineaFont.control)
                        .foregroundStyle(isSelected ? LineaColor.onInk : LineaColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: LineaMetrics.controlRadius - 2, style: .continuous)
                                    .fill(LineaColor.ink)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
                .fill(LineaColor.fill)
        )
    }
}
