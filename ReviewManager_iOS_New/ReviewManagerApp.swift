//
//  ReviewManagerApp.swift
//  ReviewManager iOS
//
//  iOS 앱 진입점 (읽기 전용)
//

import SwiftUI

@main
struct ReviewManageriOSApp: App {
    @StateObject private var syncService = SyncService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        }
    }
}
