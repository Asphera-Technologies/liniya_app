//
//  LineaHairline.swift
//  Linea
//
//  A single hairline divider. Linea separates list rows with hairlines rather
//  than boxed cards, keeping the interface flat and calm.
//

import SwiftUI

struct LineaHairline: View {
    var body: some View {
        Rectangle()
            .fill(LineaColor.separator)
            .frame(height: LineaMetrics.hairline)
            .accessibilityHidden(true)
    }
}
