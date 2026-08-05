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
    @State private var showingReleaseNotes = false

    var body: some View {
        // Bewusst ZStack statt Group: Group reicht Modifier an jedes Kind
        // einzeln weiter, wodurch das Blatt am NavigationStack des Dashboards
        // haengen bleibt und nicht erscheint.
        ZStack {
            if hasConnected {
                DashboardView()
            } else {
                OnboardingView { hasConnected = true }
            }
        }
        .sheet(isPresented: $showingReleaseNotes) {
            ReleaseNotesView {
                ReleaseNotes.markSeen()
                showingReleaseNotes = false
            }
        }
        .task {
            // Einmal je Fassung. Der Hinweis auf die neue Integration darf nicht
            // untergehen, sonst kommt in Home Assistant nichts mehr an.
            showingReleaseNotes = ReleaseNotes.isUnseen()
        }
    }
}

#Preview {
    ContentView()
}
