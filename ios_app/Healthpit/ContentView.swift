//
//  ContentView.swift
//  Healthpit
//
//  Wurzel-View: entscheidet zwischen Onboarding (Screen 0) und Dashboard
//  (Screen 1). Nach erstmaligem Verbinden wird das Onboarding übersprungen
//  (gemerkt via AppStorage). Daten laden danach ganz normal – fehlt der
//  Zugriff, greifen die Empty-States.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasConnectedHealth") private var hasConnected = false

    var body: some View {
        if hasConnected {
            DashboardView()
        } else {
            OnboardingView { hasConnected = true }
        }
    }
}

#Preview {
    ContentView()
}
