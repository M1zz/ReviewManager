//
//  SyncService.swift
//  ReviewManageriOS
//
//  CloudKit → CoreData 동기화
//

import Foundation
import CoreData
import CloudKit
import SwiftUI
import Combine

@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var syncProgress: String = ""
    @Published var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled")
            if autoSyncEnabled {
                startAutoSync()
            } else {
                stopAutoSync()
            }
        }
    }

    private let cloudKitService = CloudKitService.shared
    private let persistence = PersistenceController.shared

    private var autoSyncTimer: Timer?
    private let autoSyncInterval: TimeInterval = 1800 // 30분

    private init() {
        // 자동 동기화 설정 로드 (기본값: false - CloudKit 설정 후 수동으로 활성화)
        self.autoSyncEnabled = UserDefaults.standard.object(forKey: "autoSyncEnabled") as? Bool ?? false

        loadLastSyncDate()

        // 앱 시작 시 자동 동기화 (백그라운드에서 조용히 실행)
        if autoSyncEnabled {
            Task {
                // 에러가 나도 앱은 계속 실행
                await syncAll()
            }
            startAutoSync()
        }
    }

    // MARK: - 자동 동기화

    private func startAutoSync() {
        stopAutoSync() // 기존 타이머 정리

        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: autoSyncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.syncAll()
            }
        }

        print("✅ 자동 동기화 시작 (30분 간격)")
    }

    private func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        print("⏸️ 자동 동기화 중지")
    }

    nonisolated deinit {
        // Timer는 메인 스레드에서만 실행되므로 안전하게 invalidate
        Task { @MainActor in
            autoSyncTimer?.invalidate()
        }
    }

    // MARK: - 전체 동기화
    func syncAll() async {
        isSyncing = true
        syncError = nil
        syncProgress = "동기화 시작..."

        do {
            // 1. CloudKit에서 앱 목록 가져오기
            syncProgress = "앱 목록 가져오는 중..."
            let apps = try await cloudKitService.fetchApps()

            // 앱이 없으면 CloudKit이 설정되지 않았을 가능성이 높음
            guard !apps.isEmpty else {
                throw NSError(
                    domain: "SyncService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "CloudKit에 데이터가 없습니다. macOS 앱에서 먼저 리뷰를 조회해주세요."]
                )
            }

            print("📥 CloudKit에서 \(apps.count)개 앱 가져옴")

            // 2. CoreData에 저장
            syncProgress = "앱 정보 저장 중..."

            // 로컬 캐시된 아이콘 즉시 할당
            var appsWithCachedIcons = apps
            for i in 0..<appsWithCachedIcons.count {
                if let cachedIconURL = iTunesSearchService.getCachedIconURL(for: appsWithCachedIcons[i].bundleID) {
                    appsWithCachedIcons[i].iconURL = cachedIconURL
                }
            }

            await saveAppsToLocal(appsWithCachedIcons)

            // 3. 각 앱의 리뷰 가져오기
            for (index, app) in apps.enumerated() {
                syncProgress = "리뷰 동기화 중... (\(index + 1)/\(apps.count))"
                await syncReviews(for: app)
            }

            // 4. 완료
            lastSyncDate = Date()
            saveLastSyncDate(Date())
            isSyncing = false
            syncProgress = "동기화 완료!"

            print("✅ 전체 동기화 완료")

            // 2초 후 메시지 제거
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncProgress = ""

            // 5. 백그라운드에서 앱 아이콘 로드 (캐시 없는 것만)
            Task {
                await loadAppIconsInBackground(apps: appsWithCachedIcons)
            }

        } catch {
            // CloudKit 관련 에러를 사용자 친화적으로 변환
            let errorMessage: String
            if let ckError = error as? CKError {
                switch ckError.code {
                case .unknownItem:
                    errorMessage = "CloudKit에 데이터가 없습니다. macOS 앱에서 먼저 리뷰를 조회해주세요."
                case .notAuthenticated:
                    errorMessage = "iCloud에 로그인되어 있지 않습니다."
                case .networkUnavailable, .networkFailure:
                    errorMessage = "네트워크 연결을 확인해주세요."
                case .serverRejectedRequest:
                    errorMessage = "CloudKit 서버에 연결할 수 없습니다. 잠시 후 다시 시도해주세요."
                default:
                    errorMessage = "CloudKit 동기화 실패: \(ckError.localizedDescription)"
                }
            } else {
                errorMessage = error.localizedDescription
            }

            syncError = errorMessage
            isSyncing = false
            syncProgress = ""
            print("❌ 동기화 실패: \(errorMessage)")

            // CloudKit이 사용 불가능하면 자동 동기화 비활성화
            if let ckError = error as? CKError,
               ckError.code == .notAuthenticated || ckError.code == .unknownItem {
                print("⚠️ CloudKit 사용 불가 - 자동 동기화 비활성화")
            }
        }
    }

    // 백그라운드에서 앱 아이콘 로드
    private func loadAppIconsInBackground(apps: [AppInfo]) async {
        print("🎨 [SyncService] 아이콘 로드 시작 - 총 \(apps.count)개")

        // 1단계: 로컬에 있는 아이콘 즉시 업데이트
        for app in apps {
            if let cachedURL = iTunesSearchService.getCachedIconURL(for: app.bundleID) {
                await updateAppIcon(appID: app.id, iconURL: cachedURL)
                print("⚡️ [SyncService] 로컬 캐시 로드: \(app.bundleID)")
            }
        }

        // 2단계: 캐시 없는 앱만 다운로드
        var appsNeedingDownload: [AppInfo] = []
        for app in apps {
            if iTunesSearchService.getCachedIconURL(for: app.bundleID) == nil {
                appsNeedingDownload.append(app)
            }
        }

        guard !appsNeedingDownload.isEmpty else {
            print("✅ [SyncService] 모든 아이콘이 캐시됨")
            return
        }

        print("🔽 [SyncService] 다운로드 필요: \(appsNeedingDownload.count)개")

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
                            return (app.id, iconURL)
                        } catch {
                            print("❌ [SyncService] 다운로드 실패: \(app.bundleID)")
                            return (app.id, nil)
                        }
                    }
                }

                for await (appID, iconURL) in group {
                    if let iconURL = iconURL {
                        await updateAppIcon(appID: appID, iconURL: iconURL)
                        print("✅ [SyncService] 다운로드 완료: \(appID)")
                    }
                }
            }

            // 배치 간 짧은 딜레이
            if endIndex < appsNeedingDownload.count {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2초
            }
        }

        print("🎉 [SyncService] 아이콘 로드 완료")
    }

    // CoreData의 앱 아이콘 URL 업데이트
    private func updateAppIcon(appID: String, iconURL: String) async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            let fetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", appID)

            do {
                if let appEntity = try context.fetch(fetchRequest).first {
                    appEntity.iconURL = iconURL
                    try context.save()
                }
            } catch {
                print("❌ 아이콘 URL 업데이트 실패: \(error)")
            }
        }
    }

    // MARK: - 앱별 리뷰 동기화
    private func syncReviews(for app: AppInfo) async {
        do {
            let reviews = try await cloudKitService.fetchReviews(appID: app.id)
            print("📥 \(app.name): \(reviews.count)개 리뷰")

            await saveReviewsToLocal(reviews, appID: app.id)
        } catch {
            print("❌ 리뷰 동기화 실패 (\(app.name)): \(error.localizedDescription)")
        }
    }

    // MARK: - CoreData 저장
    private func saveAppsToLocal(_ apps: [AppInfo]) async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            for app in apps {
                let fetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", app.id)

                do {
                    let existingApps = try context.fetch(fetchRequest)
                    let appEntity: AppEntity

                    if let existing = existingApps.first {
                        appEntity = existing
                    } else {
                        appEntity = AppEntity(context: context)
                        appEntity.id = app.id
                    }

                    appEntity.name = app.name
                    appEntity.bundleID = app.bundleID
                    appEntity.sku = app.sku
                    appEntity.iconURL = app.iconURL
                    appEntity.lastSynced = Date()

                    try context.save()
                } catch {
                    print("❌ 앱 저장 실패: \(error)")
                }
            }
        }
    }

    private func saveReviewsToLocal(_ reviews: [CustomerReview], appID: String) async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            // 앱 찾기
            let appFetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
            appFetchRequest.predicate = NSPredicate(format: "id == %@", appID)

            guard let appEntity = try? context.fetch(appFetchRequest).first else {
                print("❌ 앱을 찾을 수 없음: \(appID)")
                return
            }

            for review in reviews {
                let fetchRequest: NSFetchRequest<ReviewEntity> = ReviewEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", review.id)

                do {
                    let existingReviews = try context.fetch(fetchRequest)
                    let reviewEntity: ReviewEntity

                    if let existing = existingReviews.first {
                        reviewEntity = existing
                    } else {
                        reviewEntity = ReviewEntity(context: context)
                        reviewEntity.id = review.id
                    }

                    reviewEntity.rating = Int16(review.rating)
                    reviewEntity.title = review.title
                    reviewEntity.body = review.body
                    reviewEntity.reviewerNickname = review.reviewerNickname
                    reviewEntity.createdDate = review.createdDate
                    reviewEntity.territory = review.territory
                    reviewEntity.app = appEntity

                    // 응답 저장
                    if let response = review.response {
                        let responseFetchRequest: NSFetchRequest<ResponseEntity> = ResponseEntity.fetchRequest()
                        responseFetchRequest.predicate = NSPredicate(format: "id == %@", response.id)

                        let responseEntity: ResponseEntity

                        if let existingResponse = try? context.fetch(responseFetchRequest).first {
                            responseEntity = existingResponse
                        } else {
                            responseEntity = ResponseEntity(context: context)
                            responseEntity.id = response.id
                        }

                        responseEntity.responseBody = response.responseBody
                        responseEntity.lastModifiedDate = response.lastModifiedDate
                        responseEntity.state = response.state.rawValue
                        responseEntity.review = reviewEntity

                        reviewEntity.response = responseEntity
                    }

                    try context.save()
                } catch {
                    print("❌ 리뷰 저장 실패: \(error)")
                }
            }
        }
    }

    // MARK: - 로컬 데이터 가져오기
    func fetchLocalApps() -> [AppEntity] {
        let context = persistence.viewContext
        let fetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AppEntity.name, ascending: true)]

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("❌ 로컬 앱 가져오기 실패: \(error)")
            return []
        }
    }

    func fetchLocalReviews(appID: String) -> [ReviewEntity] {
        let context = persistence.viewContext
        let fetchRequest: NSFetchRequest<ReviewEntity> = ReviewEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "app.id == %@", appID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ReviewEntity.createdDate, ascending: false)]

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("❌ 로컬 리뷰 가져오기 실패: \(error)")
            return []
        }
    }

    // MARK: - Persistence
    private func saveLastSyncDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "lastSyncDate")
    }

    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
}
