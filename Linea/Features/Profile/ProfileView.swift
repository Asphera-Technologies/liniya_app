//
//  ProfileView.swift
//  Linea
//
//  The Profile screen: a simple hairline-separated list of the user's areas
//  (about, goals, health, nutrition, documents, connections, AI provider) —
//  mirroring the Linea reference.
//

import SwiftUI

struct ProfileView: View {
    private let backend: LineaBackend = SampleBackend()

    @State private var rows: [LineaRow] = []

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Profile") {
                LineaRowList(rows: rows)
            }
        }
        .task { rows = await backend.profileSections() }
    }
}

#Preview {
    ProfileView()
        .environment(AppState())
}
