//
//  ReviewManagerApp.swift
//  ReviewManager
//
//  App Store 리뷰 관리 macOS 앱
//

import SwiftUI
import Combine
import CloudKit

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
    @Published var hiddenAppIDs: Set<String> = []

    private let apiService = AppStoreConnectService()
    private let cloudKitService = CloudKitService.shared
    private let cacheManager = CacheManager.shared

    init() {
        // 로컬에서 숨긴 앱 목록 먼저 로드
        if let savedHiddenIDs = UserDefaults.standard.array(forKey: "hiddenAppIDs") as? [String] {
            hiddenAppIDs = Set(savedHiddenIDs)
        }

        Task {
            // iCloud에서 설정 동기화
            await loadUserSettingsFromCloud()

            await loadCredentials()
            // 인증 완료 후 자동으로 앱 목록 로드 (캐시 우선)
            if isAuthenticated {
                await fetchApps(forceRefresh: false)
            }
        }
    }

    // MARK: - Hidden Apps Management
    func hideApp(_ appID: String) {
        hiddenAppIDs.insert(appID)
        saveHiddenApps()
    }

    func unhideApp(_ appID: String) {
        hiddenAppIDs.remove(appID)
        saveHiddenApps()
    }

    func isAppHidden(_ appID: String) -> Bool {
        hiddenAppIDs.contains(appID)
    }

    private func saveHiddenApps() {
        // 로컬 저장
        UserDefaults.standard.set(Array(hiddenAppIDs), forKey: "hiddenAppIDs")

        // iCloud 동기화
        if iCloudSyncEnabled {
            Task {
                do {
                    try await cloudKitService.saveHiddenApps(hiddenAppIDs)
                    print("✅ 숨긴 앱 목록 iCloud 동기화 완료")
                } catch {
                    print("❌ 숨긴 앱 목록 iCloud 동기화 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Load User Settings from iCloud
    private func loadUserSettingsFromCloud() async {
        guard iCloudSyncEnabled else { return }

        let isAvailable = await cloudKitService.isICloudAvailable()
        guard isAvailable else { return }

        do {
            // 숨긴 앱 목록 로드
            if let cloudHiddenApps = try await cloudKitService.fetchHiddenApps() {
                // iCloud 데이터가 더 최신이면 사용
                hiddenAppIDs = cloudHiddenApps
                UserDefaults.standard.set(Array(cloudHiddenApps), forKey: "hiddenAppIDs")
                print("✅ iCloud에서 숨긴 앱 목록 로드: \(cloudHiddenApps.count)개")
            }

            // 앱 순서 로드
            if let cloudAppOrder = try await cloudKitService.fetchAppOrder() {
                UserDefaults.standard.set(cloudAppOrder, forKey: "appOrder")
                print("✅ iCloud에서 앱 순서 로드: \(cloudAppOrder.count)개")
            }
        } catch {
            print("⚠️ iCloud 설정 로드 실패: \(error.localizedDescription)")
        }
    }

    // 표시할 앱 목록 (출시됨 또는 상태 미확인 + 숨기지 않음)
    var visibleApps: [AppInfo] {
        apps.filter { app in
            // versionState가 nil이면 아직 확인 안된 것이므로 일단 표시
            // 출시되지 않은 상태만 명시적으로 제외
            let isNotReleased: Bool
            if let state = app.versionState {
                isNotReleased = state != .readyForSale && state != .preorderReadyForSale
            } else {
                isNotReleased = false // nil이면 출시된 것으로 간주
            }
            let isNotHidden = !hiddenAppIDs.contains(app.id)
            return !isNotReleased && isNotHidden
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

    func fetchApps(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil

        // 캐시 확인 (forceRefresh가 false인 경우에만)
        if !forceRefresh, let cachedApps = cacheManager.getCachedApps() {
            print("📦 [AppState] 캐시된 앱 목록 사용: \(cachedApps.count)개")

            // 캐시된 데이터 사용
            var fetchedApps = cachedApps

            // 저장된 메타데이터 로드
            for i in 0..<fetchedApps.count {
                if let lastChecked = loadLastCheckedDate(for: fetchedApps[i].id) {
                    fetchedApps[i].lastCheckedDate = lastChecked
                }

                // 로컬 캐시된 아이콘 즉시 로드
                if let cachedIconURL = iTunesSearchService.getCachedIconURL(for: fetchedApps[i].bundleID) {
                    fetchedApps[i].iconURL = cachedIconURL
                }

                // 캐시된 다운로드 통계 로드
                if let cached = loadCachedDownloads(for: fetchedApps[i].id) {
                    fetchedApps[i].downloads30Days = cached.downloads
                    fetchedApps[i].downloadsLastFetched = cached.lastFetched
                }
            }

            // 저장된 순서 적용
            apps = applySavedOrder(to: fetchedApps)

            isLoading = false
            return
        }

        // 캐시가 없거나 forceRefresh인 경우 API 호출
        print("🔄 [AppState] API에서 앱 목록 조회")

        do {
            var fetchedApps = try await apiService.fetchApps()

            // 캐시에 저장
            cacheManager.cacheApps(fetchedApps)

            // 저장된 메타데이터 로드
            for i in 0..<fetchedApps.count {
                if let lastChecked = loadLastCheckedDate(for: fetchedApps[i].id) {
                    fetchedApps[i].lastCheckedDate = lastChecked
                }

                // 로컬 캐시된 아이콘 즉시 로드
                if let cachedIconURL = iTunesSearchService.getCachedIconURL(for: fetchedApps[i].bundleID) {
                    fetchedApps[i].iconURL = cachedIconURL
                }

                // 캐시된 다운로드 통계 로드
                if let cached = loadCachedDownloads(for: fetchedApps[i].id) {
                    fetchedApps[i].downloads30Days = cached.downloads
                    fetchedApps[i].downloadsLastFetched = cached.lastFetched
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

        // iCloud 동기화
        if iCloudSyncEnabled {
            Task {
                do {
                    try await cloudKitService.saveAppOrder(appIDs)
                    print("✅ 앱 순서 iCloud 동기화 완료")
                } catch {
                    print("❌ 앱 순서 iCloud 동기화 실패: \(error.localizedDescription)")
                }
            }
        }
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

    func fetchReviews(for app: AppInfo, forceRefresh: Bool = false) async {
        print("📥 [AppState] fetchReviews 시작")
        print("   앱: \(app.name) (ID: \(app.id))")
        print("   forceRefresh: \(forceRefresh)")

        isLoading = true
        errorMessage = nil
        selectedApp = app

        // 캐시 확인 (forceRefresh가 false인 경우에만)
        if !forceRefresh, let cachedReviews = cacheManager.getCachedReviews(for: app.id) {
            print("📦 [AppState] 캐시된 리뷰 사용: \(cachedReviews.count)개")
            reviews = cachedReviews
            isLoading = false
            return
        }

        // 캐시가 없거나 forceRefresh인 경우 API 호출
        print("🔄 [AppState] API에서 리뷰 조회")

        do {
            print("📡 [AppState] API 호출 시작 - fetchReviews")
            reviews = try await apiService.fetchReviews(appID: app.id)
            print("✅ [AppState] 리뷰 \(reviews.count)개 불러오기 성공")

            // 캐시에 저장
            cacheManager.cacheReviews(reviews, for: app.id)

            // CloudKit에 업로드
            if iCloudSyncEnabled {
                print("☁️ [AppState] CloudKit 업로드 시작")
                await uploadReviewsToCloudKit(app: app, reviews: reviews)
                print("✅ [AppState] CloudKit 업로드 완료")
            }

            // 마지막 확인 시간 업데이트
            saveLastCheckedDate(Date(), for: app.id)

            // 해당 앱의 뱃지 업데이트 (응답하지 않은 리뷰 개수)
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                let unansweredReviews = reviews.filter { $0.response == nil }
                apps[index].newReviewsCount = unansweredReviews.count
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
            print("❌ [AppState] 리뷰 불러오기 실패: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
        print("📥 [AppState] fetchReviews 완료")
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
        await fetchReviews(for: app, forceRefresh: true)
    }

    // MARK: - Data Sync
    func syncAll() async {
        print("🔄 [AppState] 전체 데이터 동기화 시작")

        // 1. 앱 목록 동기화
        await fetchApps(forceRefresh: true)

        // 2. 선택된 앱의 리뷰 동기화
        if let app = selectedApp {
            await fetchReviews(for: app, forceRefresh: true)
        }

        print("✅ [AppState] 전체 데이터 동기화 완료")
    }

    func clearCache() {
        cacheManager.clearAllCache()
        print("✅ [AppState] 캐시 삭제 완료")
    }

    func respondToReview(_ review: CustomerReview, response: String) async {
        print("🔵 [AppState] respondToReview 시작")
        print("   리뷰 ID: \(review.id)")
        print("   응답 길이: \(response.count)")

        isLoading = true
        errorMessage = nil

        do {
            print("📡 [AppState] API 호출 시작 - respondToReview")
            try await apiService.respondToReview(reviewID: review.id, response: response)
            print("✅ [AppState] API 호출 성공")

            print("🔄 [AppState] 리뷰 새로고침 시작")
            await refreshReviews()
            print("✅ [AppState] 리뷰 새로고침 완료")
        } catch {
            print("❌ [AppState] 에러 발생: \(error)")
            print("   에러 상세: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
        print("🔵 [AppState] respondToReview 완료")
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

    // MARK: - Unanswered Reviews Detection
    private func updateNewReviewsCounts(for apps: inout [AppInfo]) async {
        for i in 0..<apps.count {
            do {
                let reviews = try await apiService.fetchReviews(appID: apps[i].id)
                // 응답하지 않은 리뷰만 세기
                let unansweredReviews = reviews.filter { $0.response == nil }
                apps[i].newReviewsCount = unansweredReviews.count
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

    // MARK: - Download Statistics
    func fetchDownloadStatistics(for app: AppInfo) async {
        guard let vendorNumber = UserDefaults.standard.string(forKey: "vendorNumber"),
              !vendorNumber.isEmpty else {
            print("⚠️ Vendor Number가 설정되지 않았습니다")
            return
        }

        // 캐시 확인: 같은 날에 이미 가져왔으면 스킵
        if let lastFetched = app.downloadsLastFetched {
            let calendar = Calendar.current
            if calendar.isDateInToday(lastFetched) {
                print("✅ 다운로드 통계 캐시 사용 (오늘 이미 가져옴)")
                return
            }
        }

        isLoading = true

        do {
            let downloads = try await apiService.fetch30DaysDownloads(vendorNumber: vendorNumber)

            // 앱 정보 업데이트
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].downloads30Days = downloads
                apps[index].downloadsLastFetched = Date()

                // selectedApp도 업데이트
                if selectedApp?.id == app.id {
                    selectedApp = apps[index]
                }

                // UserDefaults에 캐시 저장
                UserDefaults.standard.set(downloads, forKey: "downloads_\(app.id)")
                UserDefaults.standard.set(Date(), forKey: "downloadsFetched_\(app.id)")

                print("✅ 다운로드 통계 업데이트: \(downloads)")
            }
        } catch {
            print("❌ 다운로드 통계 가져오기 실패: \(error.localizedDescription)")
            errorMessage = "다운로드 통계를 가져올 수 없습니다: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // 캐시된 다운로드 통계 로드
    private func loadCachedDownloads(for appID: String) -> (downloads: Int, lastFetched: Date)? {
        guard let downloads = UserDefaults.standard.object(forKey: "downloads_\(appID)") as? Int,
              let lastFetched = UserDefaults.standard.object(forKey: "downloadsFetched_\(appID)") as? Date else {
            return nil
        }
        return (downloads, lastFetched)
    }
}

// MARK: - Cache Manager
@MainActor
class CacheManager {
    static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // 캐시 만료 시간 (초)
    private var cacheExpirationInterval: TimeInterval {
        let hours = UserDefaults.standard.integer(forKey: "cacheExpirationHours")
        return TimeInterval(hours > 0 ? hours : 1) * 3600 // 기본 1시간
    }

    private init() {
        // 캐시 디렉토리 설정
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ReviewManagerCache", isDirectory: true)

        // 디렉토리 생성
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // ISO8601 날짜 포맷 설정
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        print("📦 [CacheManager] 초기화 완료")
        print("   캐시 디렉토리: \(cacheDirectory.path)")
        print("   캐시 만료 시간: \(cacheExpirationInterval / 3600)시간")
    }

    // MARK: - Apps Cache

    func cacheApps(_ apps: [AppInfo]) {
        let cacheData = CachedData(data: apps, timestamp: Date())
        save(cacheData, filename: "apps.json")
        print("✅ [CacheManager] 앱 목록 캐시 저장: \(apps.count)개")
    }

    func getCachedApps() -> [AppInfo]? {
        guard let cached: CachedData<[AppInfo]> = load(filename: "apps.json") else {
            print("ℹ️ [CacheManager] 캐시된 앱 목록 없음")
            return nil
        }

        if isCacheExpired(cached.timestamp) {
            print("⏰ [CacheManager] 앱 목록 캐시 만료")
            return nil
        }

        print("✅ [CacheManager] 캐시된 앱 목록 반환: \(cached.data.count)개")
        return cached.data
    }

    // MARK: - Reviews Cache

    func cacheReviews(_ reviews: [CustomerReview], for appID: String) {
        let cacheData = CachedData(data: reviews, timestamp: Date())
        save(cacheData, filename: "reviews_\(appID).json")
        print("✅ [CacheManager] 리뷰 캐시 저장: \(appID) - \(reviews.count)개")
    }

    func getCachedReviews(for appID: String) -> [CustomerReview]? {
        guard let cached: CachedData<[CustomerReview]> = load(filename: "reviews_\(appID).json") else {
            print("ℹ️ [CacheManager] 캐시된 리뷰 없음: \(appID)")
            return nil
        }

        if isCacheExpired(cached.timestamp) {
            print("⏰ [CacheManager] 리뷰 캐시 만료: \(appID)")
            return nil
        }

        print("✅ [CacheManager] 캐시된 리뷰 반환: \(appID) - \(cached.data.count)개")
        return cached.data
    }

    // MARK: - Cache Validation

    private func isCacheExpired(_ timestamp: Date) -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(timestamp)
        return elapsed > cacheExpirationInterval
    }

    // MARK: - Generic Save/Load

    private func save<T: Codable>(_ data: T, filename: String) {
        let url = cacheDirectory.appendingPathComponent(filename)
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: url)
        } catch {
            print("❌ [CacheManager] 저장 실패: \(filename) - \(error)")
        }
    }

    private func load<T: Codable>(filename: String) -> T? {
        let url = cacheDirectory.appendingPathComponent(filename)
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            // 파일이 없는 경우는 정상적인 상황이므로 에러 로그 출력 안함
            return nil
        }
    }

    // MARK: - Cache Management

    func clearAllCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try fileManager.removeItem(at: url)
            }
            print("✅ [CacheManager] 모든 캐시 삭제 완료")
        } catch {
            print("❌ [CacheManager] 캐시 삭제 실패: \(error)")
        }
    }

    func clearExpiredCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            let now = Date()

            for url in contents {
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let modificationDate = attributes[.modificationDate] as? Date else {
                    continue
                }

                let elapsed = now.timeIntervalSince(modificationDate)
                if elapsed > cacheExpirationInterval {
                    try fileManager.removeItem(at: url)
                    print("🗑️ [CacheManager] 만료된 캐시 삭제: \(url.lastPathComponent)")
                }
            }

            print("✅ [CacheManager] 만료된 캐시 정리 완료")
        } catch {
            print("❌ [CacheManager] 캐시 정리 실패: \(error)")
        }
    }

    func getCacheInfo() -> (files: Int, size: String, oldestDate: Date?) {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])

            let totalSize = contents.reduce(0) { size, url in
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return size + fileSize
            }

            let oldestDate = contents.compactMap { url -> Date? in
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.modificationDate] as? Date
            }.min()

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: Int64(totalSize))

            return (files: contents.count, size: sizeString, oldestDate: oldestDate)
        } catch {
            return (files: 0, size: "0 B", oldestDate: nil)
        }
    }
}

// MARK: - Cached Data Model
private struct CachedData<T: Codable>: Codable {
    let data: T
    let timestamp: Date
}
