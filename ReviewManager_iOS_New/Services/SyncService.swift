//
//  SyncService.swift
//  ReviewManager iOS
//
//  CloudKit → CoreData 동기화
//

import Foundation
import CoreData
import CloudKit

class SyncService: ObservableObject {
    static let shared = SyncService()

    private let cloudKitService = CloudKitService.shared
    private let persistence = PersistenceController.shared

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private init() {
        loadLastSyncDate()
    }

    // MARK: - 전체 동기화
    func syncAll() async {
        await MainActor.run {
            isSyncing = true
            syncError = nil
        }

        do {
            // 1. CloudKit에서 앱 목록 가져오기
            let apps = try await cloudKitService.fetchApps()
            print("📥 CloudKit에서 \(apps.count)개 앱 가져옴")

            // 2. CoreData에 저장
            await saveAppsToLocal(apps)

            // 3. 각 앱의 리뷰 가져오기
            for app in apps {
                await syncReviews(for: app)
            }

            // 4. 마지막 동기화 시간 저장
            await MainActor.run {
                lastSyncDate = Date()
                saveLastSyncDate(Date())
                isSyncing = false
            }

            print("✅ 동기화 완료")
        } catch {
            await MainActor.run {
                syncError = error.localizedDescription
                isSyncing = false
            }
            print("❌ 동기화 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 앱별 동기화
    func syncReviews(for app: AppInfo) async {
        do {
            let reviews = try await cloudKitService.fetchReviews(appID: app.id)
            print("📥 \(app.name): \(reviews.count)개 리뷰 가져옴")

            await saveReviewsToLocal(reviews, appID: app.id)
        } catch {
            print("❌ 리뷰 동기화 실패 (\(app.name)): \(error.localizedDescription)")
        }
    }

    // MARK: - CoreData 저장
    private func saveAppsToLocal(_ apps: [AppInfo]) async {
        let context = persistence.container.newBackgroundContext()

        await context.perform {
            for app in apps {
                let fetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", app.id)

                do {
                    let existingApps = try context.fetch(fetchRequest)
                    let appEntity: AppEntity

                    if let existing = existingApps.first {
                        // 업데이트
                        appEntity = existing
                    } else {
                        // 새로 생성
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
                    print("❌ 앱 저장 실패 (\(app.name)): \(error)")
                }
            }
        }
    }

    private func saveReviewsToLocal(_ reviews: [CustomerReview], appID: String) async {
        let context = persistence.container.newBackgroundContext()

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
                    print("❌ 리뷰 저장 실패 (\(review.id)): \(error)")
                }
            }
        }
    }

    // MARK: - 로컬 데이터 가져오기
    func fetchLocalApps() -> [AppInfo] {
        let context = persistence.viewContext
        let fetchRequest: NSFetchRequest<AppEntity> = AppEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AppEntity.name, ascending: true)]

        do {
            let appEntities = try context.fetch(fetchRequest)
            return appEntities.map { $0.toAppInfo() }
        } catch {
            print("❌ 로컬 앱 가져오기 실패: \(error)")
            return []
        }
    }

    func fetchLocalReviews(appID: String) -> [CustomerReview] {
        let context = persistence.viewContext
        let fetchRequest: NSFetchRequest<ReviewEntity> = ReviewEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "app.id == %@", appID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ReviewEntity.createdDate, ascending: false)]

        do {
            let reviewEntities = try context.fetch(fetchRequest)
            return reviewEntities.map { $0.toCustomerReview() }
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
