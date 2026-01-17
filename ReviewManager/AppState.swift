//
//  AppState.swift
//  ReviewManager
//
//  공유 앱 상태 (macOS & iOS)
//

import Foundation
import SwiftUI

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var apps: [AppInfo] = []
    @Published var selectedApp: AppInfo?
    @Published var reviews: [CustomerReview] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var iCloudSyncEnabled = true

    private let apiService = AppStoreConnectService()
    private let cloudKitService = CloudKitService.shared

    init() {
        Task {
            await loadCredentials()
        }
    }

    func loadCredentials() async {
        // 먼저 로컬에서 로드 시도
        if let issuerID = UserDefaults.standard.string(forKey: "issuerID"),
           let keyID = UserDefaults.standard.string(forKey: "keyID"),
           let privateKey = UserDefaults.standard.string(forKey: "privateKey"),
           !issuerID.isEmpty, !keyID.isEmpty, !privateKey.isEmpty {
            apiService.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
            isAuthenticated = true
            return
        }

        // 로컬에 없으면 iCloud에서 로드 시도
        if iCloudSyncEnabled && await cloudKitService.isICloudAvailable() {
            do {
                if let credentials = try await cloudKitService.fetchCredentials() {
                    // iCloud에서 가져온 인증 정보를 로컬에도 저장
                    UserDefaults.standard.set(credentials.issuerID, forKey: "issuerID")
                    UserDefaults.standard.set(credentials.keyID, forKey: "keyID")
                    UserDefaults.standard.set(credentials.privateKey, forKey: "privateKey")

                    apiService.configure(issuerID: credentials.issuerID, keyID: credentials.keyID, privateKey: credentials.privateKey)
                    isAuthenticated = true
                }
            } catch {
                print("iCloud에서 인증 정보 로드 실패: \(error.localizedDescription)")
            }
        }
    }

    func configure(issuerID: String, keyID: String, privateKey: String) {
        // 로컬 저장
        UserDefaults.standard.set(issuerID, forKey: "issuerID")
        UserDefaults.standard.set(keyID, forKey: "keyID")
        UserDefaults.standard.set(privateKey, forKey: "privateKey")

        apiService.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
        isAuthenticated = true

        // iCloud 동기화
        if iCloudSyncEnabled {
            Task {
                do {
                    try await cloudKitService.saveCredentials(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
                } catch {
                    print("iCloud 동기화 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "issuerID")
        UserDefaults.standard.removeObject(forKey: "keyID")
        UserDefaults.standard.removeObject(forKey: "privateKey")

        isAuthenticated = false
        apps = []
        selectedApp = nil
        reviews = []
    }

    func fetchApps() async {
        isLoading = true
        errorMessage = nil

        do {
            var fetchedApps = try await apiService.fetchApps()

            // 저장된 메타데이터 로드
            for i in 0..<fetchedApps.count {
                if let lastChecked = loadLastCheckedDate(for: fetchedApps[i].id) {
                    fetchedApps[i].lastCheckedDate = lastChecked
                }
            }

            // 앱 아이콘 URL 가져오기
            let bundleIDs = fetchedApps.map { $0.bundleID }
            let icons = await iTunesSearchService.shared.fetchAppIcons(bundleIDs: bundleIDs)

            for i in 0..<fetchedApps.count {
                if let iconURL = icons[fetchedApps[i].bundleID] {
                    fetchedApps[i].iconURL = iconURL
                }
            }

            // 새 리뷰 수 계산
            await updateNewReviewsCounts(for: &fetchedApps)

            // 뱃지 수에 따라 정렬 (뱃지 많은 순 -> 이름순)
            apps = fetchedApps.sorted { app1, app2 in
                if app1.newReviewsCount != app2.newReviewsCount {
                    return app1.newReviewsCount > app2.newReviewsCount
                }
                return app1.name < app2.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchReviews(for app: AppInfo) async {
        isLoading = true
        errorMessage = nil
        selectedApp = app

        do {
            reviews = try await apiService.fetchReviews(appID: app.id)

            // CloudKit에 업로드
            if iCloudSyncEnabled {
                await uploadReviewsToCloudKit(app: app, reviews: reviews)
            }

            // 마지막 확인 시간 업데이트
            saveLastCheckedDate(Date(), for: app.id)

            // 해당 앱의 뱃지 초기화
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].newReviewsCount = 0
                apps[index].lastCheckedDate = Date()

                // 정렬 업데이트
                apps.sort { app1, app2 in
                    if app1.newReviewsCount != app2.newReviewsCount {
                        return app1.newReviewsCount > app2.newReviewsCount
                    }
                    return app1.name < app2.name
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - CloudKit Upload
    private func uploadReviewsToCloudKit(app: AppInfo, reviews: [CustomerReview]) async {
        do {
            // 앱 정보 업로드
            try await cloudKitService.saveApp(app)

            // 리뷰 업로드
            for review in reviews {
                try await cloudKitService.saveReview(review, appID: app.id)
            }

            print("✅ CloudKit 업로드 완료: \(app.name) - \(reviews.count)개 리뷰")
        } catch {
            print("❌ CloudKit 업로드 실패: \(error.localizedDescription)")
        }
    }

    func refreshReviews() async {
        guard let app = selectedApp else { return }
        await fetchReviews(for: app)
    }

    func respondToReview(_ review: CustomerReview, response: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await apiService.respondToReview(reviewID: review.id, response: response)
            await refreshReviews()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteResponse(for review: CustomerReview) async {
        guard let responseID = review.response?.id else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await apiService.deleteResponse(responseID: responseID)
            await refreshReviews()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - New Reviews Detection
    private func updateNewReviewsCounts(for apps: inout [AppInfo]) async {
        for i in 0..<apps.count {
            guard let lastChecked = apps[i].lastCheckedDate else {
                // 한 번도 확인하지 않은 앱은 뱃지 표시 안 함
                apps[i].newReviewsCount = 0
                continue
            }

            do {
                let reviews = try await apiService.fetchReviews(appID: apps[i].id)
                let newReviews = reviews.filter { $0.createdDate > lastChecked }
                apps[i].newReviewsCount = newReviews.count
            } catch {
                apps[i].newReviewsCount = 0
            }
        }
    }

    // MARK: - Persistence
    private func saveLastCheckedDate(_ date: Date, for appID: String) {
        // 로컬 저장
        UserDefaults.standard.set(date, forKey: "lastChecked_\(appID)")

        // iCloud 동기화
        if iCloudSyncEnabled {
            Task {
                do {
                    try await cloudKitService.saveAppMetadata(appID: appID, lastCheckedDate: date)
                } catch {
                    print("iCloud에 메타데이터 저장 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadLastCheckedDate(for appID: String) -> Date? {
        return UserDefaults.standard.object(forKey: "lastChecked_\(appID)") as? Date
    }

    private func loadAppMetadata() {
        // 앱 시작 시 iCloud에서 메타데이터 로드
        if iCloudSyncEnabled {
            Task {
                do {
                    let metadata = try await cloudKitService.fetchAllAppMetadata()

                    // 로컬에 저장
                    for (appID, lastChecked) in metadata {
                        UserDefaults.standard.set(lastChecked, forKey: "lastChecked_\(appID)")
                    }
                } catch {
                    print("iCloud에서 메타데이터 로드 실패: \(error.localizedDescription)")
                }
            }
        }
    }
}
