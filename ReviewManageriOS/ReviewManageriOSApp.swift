//
//  ReviewManageriOSApp.swift
//  ReviewManageriOS
//
//  iOS 앱 진입점
//

import SwiftUI
import Combine

@main
struct ReviewManageriOSApp: App {
    @StateObject private var syncService = SyncService.shared
    @StateObject private var apiState = APIState()
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
                .environmentObject(apiState)
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
    }
}

// MARK: - API State
@MainActor
class APIState: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false

    private let apiService = AppStoreConnectService()
    private let cloudKitService = CloudKitService.shared

    init() {
        Task {
            await loadCredentials()
        }
    }

    func loadCredentials() async {
        // 1. 먼저 로컬 UserDefaults에서 시도
        if let issuerID = UserDefaults.standard.string(forKey: "issuerID"),
           let keyID = UserDefaults.standard.string(forKey: "keyID"),
           let privateKey = UserDefaults.standard.string(forKey: "privateKey"),
           !issuerID.isEmpty, !keyID.isEmpty, !privateKey.isEmpty {
            apiService.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
            isAuthenticated = true
            print("✅ [iOS APIState] 로컬에서 인증 정보 로드 완료")
            return
        }

        // 2. CloudKit에서 인증 정보 가져오기
        do {
            if let credentials = try await cloudKitService.fetchCredentials() {
                // 로컬에 저장
                UserDefaults.standard.set(credentials.issuerID, forKey: "issuerID")
                UserDefaults.standard.set(credentials.keyID, forKey: "keyID")
                UserDefaults.standard.set(credentials.privateKey, forKey: "privateKey")

                // API 서비스 설정
                apiService.configure(issuerID: credentials.issuerID, keyID: credentials.keyID, privateKey: credentials.privateKey)
                isAuthenticated = true
                print("✅ [iOS APIState] CloudKit에서 인증 정보 로드 완료")
            } else {
                print("⚠️ [iOS APIState] CloudKit에 인증 정보가 없습니다")
                isAuthenticated = false
            }
        } catch {
            print("❌ [iOS APIState] 인증 정보 로드 실패: \(error.localizedDescription)")
            isAuthenticated = false
        }
    }

    func respondToReview(reviewID: String, response: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await apiService.respondToReview(reviewID: reviewID, response: response)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    func deleteResponse(responseID: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await apiService.deleteResponse(responseID: responseID)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            throw error
        }
    }
}
