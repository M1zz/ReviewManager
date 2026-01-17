//
//  ReviewManagerApp.swift
//  ReviewManager
//
//  App Store 리뷰 관리 macOS 앱
//

import SwiftUI
import Combine

@main
struct ReviewManagerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("리뷰") {
                Button("새로고침") {
                    Task {
                        await appState.refreshReviews()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

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
    @Published var backupProgress: String?
    @Published var isBackingUp = false

    private let apiService = AppStoreConnectService()
    private let cloudKitService = CloudKitService.shared

    init() {
        Task {
            await loadCredentials()
            // 인증 완료 후 자동으로 앱 목록 로드
            if isAuthenticated {
                await fetchApps()
            }
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
        if iCloudSyncEnabled {
            let isAvailable = await cloudKitService.isICloudAvailable()
            if isAvailable {
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

        // 인증 완료 후 자동으로 앱 목록 로드
        Task {
            await fetchApps()
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

                // 로컬 캐시된 아이콘 즉시 로드
                if let cachedIconURL = iTunesSearchService.getCachedIconURL(for: fetchedApps[i].bundleID) {
                    fetchedApps[i].iconURL = cachedIconURL
                }
            }

            // 새 리뷰 수 계산
            await updateNewReviewsCounts(for: &fetchedApps)

            // 저장된 순서 적용
            apps = applySavedOrder(to: fetchedApps)

            // CloudKit에 앱 목록 업로드
            if iCloudSyncEnabled {
                Task {
                    await uploadAppsToCloudKit(apps: apps)
                }
            }

            // 앱 목록을 먼저 표시한 후, 아이콘은 백그라운드에서 비동기로 로드
            isLoading = false

            Task { @MainActor in
                await loadAppIconsInBackground()
            }

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - CloudKit Upload Apps
    private func uploadAppsToCloudKit(apps: [AppInfo]) async {
        do {
            for app in apps {
                try await cloudKitService.saveApp(app)
            }
            print("✅ CloudKit 앱 목록 업로드 완료: \(apps.count)개")
        } catch {
            print("❌ CloudKit 앱 목록 업로드 실패: \(error.localizedDescription)")
        }
    }

    // 앱 순서 저장
    func saveAppOrder() {
        let appIDs = apps.map { $0.id }
        UserDefaults.standard.set(appIDs, forKey: "appOrder")
        print("✅ [AppState] 앱 순서 저장: \(appIDs)")
    }

    // 저장된 순서 적용
    private func applySavedOrder(to apps: [AppInfo]) -> [AppInfo] {
        guard let savedOrder = UserDefaults.standard.array(forKey: "appOrder") as? [String] else {
            // 저장된 순서가 없으면 뱃지순 정렬
            return apps.sorted { app1, app2 in
                if app1.newReviewsCount != app2.newReviewsCount {
                    return app1.newReviewsCount > app2.newReviewsCount
                }
                return app1.name < app2.name
            }
        }

        // 저장된 순서대로 정렬
        var orderedApps: [AppInfo] = []
        var remainingApps = apps

        // 저장된 순서에 따라 배치
        for appID in savedOrder {
            if let index = remainingApps.firstIndex(where: { $0.id == appID }) {
                orderedApps.append(remainingApps.remove(at: index))
            }
        }

        // 새로 추가된 앱들은 뱃지순으로 마지막에 추가
        let newApps = remainingApps.sorted { app1, app2 in
            if app1.newReviewsCount != app2.newReviewsCount {
                return app1.newReviewsCount > app2.newReviewsCount
            }
            return app1.name < app2.name
        }

        orderedApps.append(contentsOf: newApps)

        return orderedApps
    }

    // 앱 순서 변경
    func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        saveAppOrder()
    }

    // 백그라운드에서 아이콘 비동기 로드
    private func loadAppIconsInBackground() async {
        guard !apps.isEmpty else { return }

        print("🎨 [AppState] 아이콘 로드 시작 - 총 \(apps.count)개")

        // 1단계: 로컬에 있는 아이콘 즉시 로드
        for (index, app) in apps.enumerated() {
            if let cachedURL = iTunesSearchService.getCachedIconURL(for: app.bundleID) {
                apps[index].iconURL = cachedURL
                print("⚡️ [AppState] 로컬 캐시 로드: \(app.bundleID)")
            }
        }

        // 2단계: 캐시 없는 앱만 다운로드
        let appsNeedingDownload = apps.filter { $0.iconURL == nil }

        guard !appsNeedingDownload.isEmpty else {
            print("✅ [AppState] 모든 아이콘이 캐시됨")
            return
        }

        print("🔽 [AppState] 다운로드 필요: \(appsNeedingDownload.count)개")

        // 3단계: 동시성 제한하여 다운로드 (최대 3개씩)
        let batchSize = 3
        for startIndex in stride(from: 0, to: appsNeedingDownload.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, appsNeedingDownload.count)
            let batch = Array(appsNeedingDownload[startIndex..<endIndex])

            await withTaskGroup(of: (String, String?).self) { group in
                for app in batch {
                    group.addTask {
                        do {
                            let iconURL = try await iTunesSearchService.shared.fetchAppIcon(bundleID: app.bundleID)
                            return (app.bundleID, iconURL)
                        } catch {
                            print("❌ [AppState] 다운로드 실패: \(app.bundleID)")
                            return (app.bundleID, nil)
                        }
                    }
                }

                for await (bundleID, iconURL) in group {
                    if let iconURL = iconURL,
                       let appIndex = apps.firstIndex(where: { $0.bundleID == bundleID }) {
                        apps[appIndex].iconURL = iconURL
                        print("✅ [AppState] 다운로드 완료: \(bundleID)")
                    }
                }
            }

            // 배치 간 짧은 딜레이
            if endIndex < appsNeedingDownload.count {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2초
            }
        }

        print("🎉 [AppState] 아이콘 로드 완료")
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

    // MARK: - Manual Backup
    func backupAllToCloudKit() async {
        guard !isBackingUp else { return }

        isBackingUp = true
        backupProgress = "백업 시작..."

        do {
            // 1. 모든 앱 백업
            backupProgress = "앱 정보 백업 중..."
            for app in apps {
                try await cloudKitService.saveApp(app)
            }
            print("✅ \(apps.count)개 앱 백업 완료")

            // 2. 각 앱의 모든 리뷰 백업
            for (index, app) in apps.enumerated() {
                backupProgress = "리뷰 백업 중... (\(index + 1)/\(apps.count))"

                // 해당 앱의 리뷰를 API에서 가져오기
                do {
                    let reviews = try await apiService.fetchReviews(appID: app.id)

                    // CloudKit에 업로드
                    for review in reviews {
                        try await cloudKitService.saveReview(review, appID: app.id)
                    }

                    print("✅ \(app.name): \(reviews.count)개 리뷰 백업 완료")
                } catch {
                    print("⚠️ \(app.name) 리뷰 백업 실패: \(error.localizedDescription)")
                }
            }

            // 3. 메타데이터 백업
            backupProgress = "메타데이터 백업 중..."
            for app in apps {
                if let lastChecked = loadLastCheckedDate(for: app.id) {
                    try await cloudKitService.saveAppMetadata(appID: app.id, lastCheckedDate: lastChecked)
                }
            }

            backupProgress = "✅ 백업 완료!"
            print("✅ 전체 백업 완료")

            // 3초 후 메시지 제거
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            backupProgress = nil

        } catch {
            backupProgress = "❌ 백업 실패: \(error.localizedDescription)"
            print("❌ 백업 실패: \(error.localizedDescription)")

            // 5초 후 에러 메시지 제거
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            backupProgress = nil
        }

        isBackingUp = false
    }
}
