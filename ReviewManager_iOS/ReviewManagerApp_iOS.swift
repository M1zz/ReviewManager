//
//  ReviewManagerApp_iOS.swift
//  ReviewManager (iOS)
//
//  iOS 앱 진입점
//

import SwiftUI

@main
struct ReviewManagerApp_iOS: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView_iOS()
                .environmentObject(appState)
        }
    }
}
