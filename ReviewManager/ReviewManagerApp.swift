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

    // MARK: - Priority Dashboard
    @Published var scoredApps: [ScoredApp] = []
    @Published var isAnalyzing = false
    @Published var analyzeProgress: String?
    @Published var lastAnalyzedDate: Date?
    /// 디스크에 저장되는 분석 기록 (최신순). 날짜를 눌러 과거 결과를 다시 볼 수 있다.
    @Published var analysisHistory: [AnalysisSnapshot] = []

    // MARK: - Demo Mode
    /// 인증 없이 샘플 데이터로 전체 기능을 체험하는 모드 (App Review Guideline 2.1 대응).
    @Published var isDemoMode = false
    private var demoReviews: [String: [CustomerReview]] = [:]
    private var demoSales: [String: SalesData] = [:]

    /// 데모 모드 진입: 샘플 앱·리뷰·판매·통계·우선순위 점수를 메모리에 채운다.
    func enterDemoMode() {
        let bundle = DemoData.make()
        demoReviews = bundle.reviews
        demoSales = bundle.sales

        isDemoMode = true
        iCloudSyncEnabled = false      // 데모에서는 외부 동기화 비활성화
        errorMessage = nil
        apps = bundle.apps
        selectedApp = nil
        reviews = []
        scoredApps = Scorer.score(apps: bundle.apps, sales: bundle.sales, reviews: bundle.reviews)
        lastAnalyzedDate = Date()
        isAuthenticated = true
        print("🎭 [AppState] 데모 모드 진입: 앱 \(apps.count)개")
    }

    private let apiService = AppStoreConnectService()
    private let cloudKitService = CloudKitService.shared
    private let cacheManager = CacheManager.shared

    init() {
        // 로컬에서 숨긴 앱 목록 먼저 로드
        if let savedHiddenIDs = UserDefaults.standard.array(forKey: "hiddenAppIDs") as? [String] {
            hiddenAppIDs = Set(savedHiddenIDs)
        }

        // 저장된 분석 기록 로드 → 최신 결과를 바로 표시
        loadAnalysisHistory()
        if let latest = analysisHistory.first {
            scoredApps = latest.apps
            lastAnalyzedDate = latest.date
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

        // 데모 모드 상태 초기화
        isDemoMode = false
        demoReviews = [:]
        demoSales = [:]
        scoredApps = []
        lastAnalyzedDate = nil

        isAuthenticated = false
        apps = []
        selectedApp = nil
        reviews = []
    }

    func fetchApps(forceRefresh: Bool = false) async {
        // 데모 모드에서는 샘플 앱 목록을 그대로 유지한다.
        if isDemoMode {
            isLoading = false
            return
        }

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

        // 데모 모드: 샘플 리뷰를 메모리에서 바로 제공 (API 호출 없음)
        if isDemoMode {
            reviews = demoReviews[app.id] ?? []
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].newReviewsCount = reviews.filter { $0.response == nil }.count
            }
            isLoading = false
            return
        }

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

        // 데모 모드: 실제 전송 없이 로컬 샘플 데이터에만 응답을 반영한다.
        if isDemoMode {
            applyDemoResponse(reviewID: review.id, body: response)
            isLoading = false
            return
        }

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

        _ = responseID
        isLoading = true
        errorMessage = nil

        // 데모 모드: 로컬 샘플 데이터에서만 응답 제거
        if isDemoMode {
            removeDemoResponse(reviewID: review.id)
            isLoading = false
            return
        }

        do {
            try await apiService.deleteResponse(responseID: responseID)
            await refreshReviews()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Demo Mode Helpers

    private func applyDemoResponse(reviewID: String, body: String) {
        let response = ReviewResponse(
            id: "demo-resp-\(reviewID)",
            responseBody: body,
            lastModifiedDate: Date(),
            state: .published
        )
        mutateDemoReview(reviewID: reviewID) { $0.response = response }
    }

    private func removeDemoResponse(reviewID: String) {
        mutateDemoReview(reviewID: reviewID) { $0.response = nil }
    }

    /// 데모 리뷰 저장소와 현재 표시 중인 리뷰 목록·뱃지를 함께 갱신한다.
    private func mutateDemoReview(reviewID: String, _ transform: (inout CustomerReview) -> Void) {
        for (appID, var list) in demoReviews {
            if let idx = list.firstIndex(where: { $0.id == reviewID }) {
                transform(&list[idx])
                demoReviews[appID] = list
                // 현재 보고 있는 앱이면 화면 목록도 갱신
                if selectedApp?.id == appID {
                    reviews = list
                }
                // 뱃지(미응답 수) 갱신
                if let aIdx = apps.firstIndex(where: { $0.id == appID }) {
                    apps[aIdx].newReviewsCount = list.filter { $0.response == nil }.count
                }
                break
            }
        }
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
        if isDemoMode {
            backupProgress = "데모 모드에서는 백업을 사용할 수 없습니다."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            backupProgress = nil
            return
        }

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

    // MARK: - Analytics

    // Analytics Report Request 생성 또는 가져오기
    func ensureAnalyticsReportRequest(for app: AppInfo) async throws -> String {
        if isDemoMode {
            return app.analyticsRequestInfo?.requestId ?? "demo-req-\(app.id)"
        }
        // 이미 요청이 있는지 확인
        if let existingRequest = app.analyticsRequestInfo, existingRequest.isActive {
            print("✅ [AppState] 기존 Analytics 요청 사용: \(existingRequest.requestId)")
            return existingRequest.requestId
        }

        // 새 요청 생성
        print("📊 [AppState] 새 Analytics 요청 생성")
        let requestId = try await apiService.createAnalyticsReportRequest(appID: app.id)

        // 앱 정보에 저장
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].analyticsRequestInfo = AnalyticsReportRequestInfo(
                requestId: requestId,
                appId: app.id,
                accessType: "ONGOING",
                createdDate: Date(),
                stoppedDueToInactivity: false,
                lastCheckedDate: Date()
            )

            // selectedApp도 업데이트
            if selectedApp?.id == app.id {
                selectedApp = apps[index]
            }

            // 캐시에 저장
            cacheManager.cacheApps(apps)
            print("💾 [AppState] Analytics 요청 정보 캐시 저장 완료")
        }

        return requestId
    }

    // Analytics 데이터 가져오기
    func fetchAnalytics(for app: AppInfo) async throws -> AnalyticsData {
        print("📊 [AppState] fetchAnalytics 시작: \(app.name)")

        if isDemoMode {
            return app.analytics ?? AnalyticsData()
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 1. Report Request 확인/생성
            let requestId = try await ensureAnalyticsReportRequest(for: app)

            // 2. 상태 확인
            let status = try await apiService.checkAnalyticsReportRequestStatus(requestId: requestId)

            // 비활성 상태면 업데이트
            if status.stoppedDueToInactivity {
                if let index = apps.firstIndex(where: { $0.id == app.id }) {
                    apps[index].analyticsRequestInfo?.stoppedDueToInactivity = true
                    if selectedApp?.id == app.id {
                        selectedApp = apps[index]
                    }
                }
                throw ServiceError.reportNotReady
            }

            // 3. Analytics 데이터 조회
            let analytics = try await apiService.fetchAnalyticsData(appID: app.id, requestId: requestId)

            // 4. 앱 정보 업데이트
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].analytics = analytics
                apps[index].analyticsRequestInfo?.lastCheckedDate = Date()

                // selectedApp도 업데이트
                if selectedApp?.id == app.id {
                    selectedApp = apps[index]
                }

                // 캐시에 저장
                cacheManager.cacheApps(apps)
                print("💾 [AppState] Analytics 데이터 캐시 저장 완료")

                print("✅ [AppState] Analytics 업데이트 완료")
                print("   노출 수: \(analytics.impressions)")
                print("   페이지 조회: \(analytics.pageViews)")
                print("   설치: \(analytics.installs)")
            }

            return analytics
        } catch {
            print("❌ [AppState] Analytics 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // Analytics Report Request 삭제
    func deleteAnalyticsReportRequest(for app: AppInfo) async throws {
        guard let requestInfo = app.analyticsRequestInfo else {
            return
        }

        print("🗑️ [AppState] Analytics 요청 삭제: \(requestInfo.requestId)")

        // API 호출로 삭제 (DELETE /analyticsReportRequests/{id})
        // 여기서는 로컬 상태만 제거
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].analyticsRequestInfo = nil
            apps[index].analytics = nil

            if selectedApp?.id == app.id {
                selectedApp = apps[index]
            }
        }

        print("✅ [AppState] Analytics 요청 삭제 완료")
    }

    // MARK: - Sales Data

    // Sales 데이터 가져오기 (스마트 캐싱)
    func fetchSalesData(for app: AppInfo, days: Int = 30) async throws -> SalesData {
        if isDemoMode {
            return demoSales[app.id] ?? app.salesData ?? SalesData()
        }
        guard let vendorNumber = UserDefaults.standard.string(forKey: "vendorNumber"),
              !vendorNumber.isEmpty else {
            throw ServiceError.invalidData
        }

        print("📊 [AppState] fetchSalesData 시작: \(app.name)")

        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let requestedStartDate = calendar.date(byAdding: .day, value: -days + 1, to: today) ?? today

        // 기존 캐시 데이터 확인
        var existingSalesData = app.salesData ?? SalesData()

        // 이미 캐시된 날짜들 확인
        let cachedDates = Set(existingSalesData.dailyData.map { calendar.startOfDay(for: $0.date) })

        print("📊 [AppState] 캐시 확인:")
        print("   요청 기간: \(days)일")
        print("   이미 캐시된 날짜: \(cachedDates.count)개")

        // 캐시되지 않은 날짜만 필터링
        var datesToFetch: [Date] = []
        for daysAgo in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) {
                let dateOnly = calendar.startOfDay(for: date)
                if !cachedDates.contains(dateOnly) {
                    datesToFetch.append(dateOnly)
                }
            }
        }

        print("   새로 가져올 날짜: \(datesToFetch.count)개")

        // 새로 가져올 데이터가 없으면 캐시 반환
        if datesToFetch.isEmpty {
            print("✅ [AppState] 모든 데이터가 캐시됨, API 호출 스킵")
            return existingSalesData
        }

        do {
            // 캐시되지 않은 날짜만 API 호출
            let newSalesData = try await apiService.fetchSalesDataForDates(
                vendorNumber: vendorNumber,
                dates: datesToFetch
            )

            // 기존 데이터와 병합
            existingSalesData.merge(with: newSalesData)

            // 날짜 범위 업데이트
            if let earliest = existingSalesData.dailyData.map({ $0.date }).min() {
                existingSalesData.earliestDate = earliest
            }
            if let latest = existingSalesData.dailyData.map({ $0.date }).max() {
                existingSalesData.latestDate = latest
            }

            // 앱 정보 업데이트
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].salesData = existingSalesData
                apps[index].downloads30Days = existingSalesData.totalUnits
                apps[index].downloadsLastFetched = Date()

                // selectedApp도 업데이트
                if selectedApp?.id == app.id {
                    selectedApp = apps[index]
                }

                // 캐시에 저장
                cacheManager.cacheApps(apps)
                print("💾 [AppState] Sales 데이터 캐시 저장 완료")

                print("✅ [AppState] Sales 데이터 업데이트 완료")
                print("   새로 가져온 날짜: \(datesToFetch.count)개")
                print("   총 판매: \(existingSalesData.totalUnits)")
                print("   총 수익: $\(String(format: "%.2f", existingSalesData.totalRevenue))")
                print("   국가 수: \(existingSalesData.countryData.count)")
                print("   일별 데이터: \(existingSalesData.dailyData.count)일")
            }

            return existingSalesData
        } catch {
            print("❌ [AppState] Sales 데이터 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Priority Dashboard Scoring

    /// 이미 캐시된 데이터(앱별 salesData + 캐시된 리뷰)만으로 즉시 점수 계산.
    /// API 호출 없이 대시보드를 바로 채우는 용도.
    func computeScoresFromCache() {
        let targets = visibleApps
        var salesMap: [String: SalesData] = [:]
        var reviewsMap: [String: [CustomerReview]] = [:]

        for app in targets {
            if let sales = app.salesData {
                salesMap[app.id] = sales
            }
            if let cachedReviews = cacheManager.getCachedReviews(for: app.id) {
                reviewsMap[app.id] = cachedReviews
            }
        }

        scoredApps = Scorer.score(apps: targets, sales: salesMap, reviews: reviewsMap)
        print("📊 [AppState] 캐시 기반 점수 계산: \(scoredApps.count)개 앱")
    }

    /// 모든 표시 앱의 판매 데이터 + 리뷰를 가져와 점수를 재계산.
    /// (앱당 최대 salesDays개의 판매 보고서 + 리뷰를 호출하므로 시간이 걸립니다.)
    func analyzeAllApps(salesDays: Int = 30) async {
        guard !isAnalyzing else { return }

        // 데모 모드: 샘플 데이터로 즉시 점수 재계산
        if isDemoMode {
            scoredApps = Scorer.score(apps: visibleApps, sales: demoSales, reviews: demoReviews)
            lastAnalyzedDate = Date()
            return
        }

        isAnalyzing = true
        analyzeProgress = "분석 준비 중..."
        defer {
            isAnalyzing = false
            analyzeProgress = nil
        }

        let targets = visibleApps
        let hasVendorNumber = !(UserDefaults.standard.string(forKey: "vendorNumber")?.isEmpty ?? true)

        var salesMap: [String: SalesData] = [:]
        var reviewsMap: [String: [CustomerReview]] = [:]

        for (index, app) in targets.enumerated() {
            analyzeProgress = "분석 중... (\(index + 1)/\(targets.count)) \(app.name)"

            // 판매 데이터: Vendor Number가 있으면 새로 가져오고, 없으면 캐시 사용
            if hasVendorNumber {
                if let sales = try? await fetchSalesData(for: app, days: salesDays) {
                    salesMap[app.id] = sales
                } else if let cached = app.salesData {
                    salesMap[app.id] = cached
                }
            } else if let cached = app.salesData {
                salesMap[app.id] = cached
            }

            // 리뷰: 캐시 우선, 없으면 API 호출
            if let cachedReviews = cacheManager.getCachedReviews(for: app.id) {
                reviewsMap[app.id] = cachedReviews
            } else if let fetched = try? await apiService.fetchReviews(appID: app.id) {
                cacheManager.cacheReviews(fetched, for: app.id)
                reviewsMap[app.id] = fetched
            }
        }

        scoredApps = Scorer.score(apps: targets, sales: salesMap, reviews: reviewsMap)
        recordAnalysisSnapshot()
        print("✅ [AppState] 전체 분석 완료: \(scoredApps.count)개 앱 점수화")
    }

    /// 현재 scoredApps를 새 스냅샷으로 기록하고 디스크에 저장. (데모 모드 제외)
    private func recordAnalysisSnapshot() {
        let now = Date()
        lastAnalyzedDate = now
        guard !isDemoMode, !scoredApps.isEmpty else { return }

        let snapshot = AnalysisSnapshot(id: UUID().uuidString, date: now, apps: scoredApps)
        analysisHistory.insert(snapshot, at: 0)
        if analysisHistory.count > 20 {
            analysisHistory = Array(analysisHistory.prefix(20))
        }
        saveAnalysisHistory()
    }

    /// 과거 분석 결과를 다시 표시한다.
    func showSnapshot(_ snapshot: AnalysisSnapshot) {
        scoredApps = snapshot.apps
        lastAnalyzedDate = snapshot.date
    }

    // MARK: - Analysis History Persistence

    private var analysisHistoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReviewManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("analysis_history.json")
    }

    private func loadAnalysisHistory() {
        guard let data = try? Data(contentsOf: analysisHistoryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let history = try? decoder.decode([AnalysisSnapshot].self, from: data) {
            analysisHistory = history.sorted { $0.date > $1.date }
            print("📂 [AppState] 분석 기록 로드: \(analysisHistory.count)건")
        }
    }

    private func saveAnalysisHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(analysisHistory)
            try data.write(to: analysisHistoryURL)
            print("💾 [AppState] 분석 기록 저장: \(analysisHistory.count)건")
        } catch {
            print("❌ [AppState] 분석 기록 저장 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Download Statistics
    func fetchDownloadStatistics(for app: AppInfo) async {
        if isDemoMode { return }   // 데모 데이터에 이미 다운로드 수가 채워져 있음

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
