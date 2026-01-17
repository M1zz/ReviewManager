//
//  CloudKitService.swift
//  ReviewManager
//
//  CloudKit 동기화 서비스
//

import Foundation
import CloudKit

class CloudKitService {
    static let shared = CloudKitService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    // Record Types
    private let credentialsRecordType = "APICredentials"
    private let appMetadataRecordType = "AppMetadata"
    private let appRecordType = "App"
    private let reviewRecordType = "Review"
    private let responseRecordType = "ReviewResponse"

    private init() {
        container = CKContainer.default()
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - API Credentials Sync

    /// API 인증 정보를 CloudKit에 저장
    func saveCredentials(issuerID: String, keyID: String, privateKey: String) async throws {
        let recordID = CKRecord.ID(recordName: "credentials")
        let record = CKRecord(recordType: credentialsRecordType, recordID: recordID)

        record["issuerID"] = issuerID as CKRecordValue
        record["keyID"] = keyID as CKRecordValue
        record["privateKey"] = privateKey as CKRecordValue
        record["lastModified"] = Date() as CKRecordValue

        try await privateDatabase.save(record)
    }

    /// CloudKit에서 API 인증 정보 불러오기
    func fetchCredentials() async throws -> (issuerID: String, keyID: String, privateKey: String)? {
        let recordID = CKRecord.ID(recordName: "credentials")

        do {
            let record = try await privateDatabase.record(for: recordID)

            guard let issuerID = record["issuerID"] as? String,
                  let keyID = record["keyID"] as? String,
                  let privateKey = record["privateKey"] as? String else {
                return nil
            }

            return (issuerID, keyID, privateKey)
        } catch let error as CKError where error.code == .unknownItem {
            // 레코드가 없으면 nil 반환
            return nil
        }
    }

    /// API 인증 정보 삭제
    func deleteCredentials() async throws {
        let recordID = CKRecord.ID(recordName: "credentials")
        try await privateDatabase.deleteRecord(withID: recordID)
    }

    // MARK: - App Metadata Sync

    /// 앱 메타데이터 (마지막 확인 시간) 저장
    func saveAppMetadata(appID: String, lastCheckedDate: Date) async throws {
        let recordID = CKRecord.ID(recordName: "app_\(appID)")
        let record = CKRecord(recordType: appMetadataRecordType, recordID: recordID)

        record["appID"] = appID as CKRecordValue
        record["lastCheckedDate"] = lastCheckedDate as CKRecordValue

        try await privateDatabase.save(record)
    }

    /// 특정 앱의 메타데이터 불러오기
    func fetchAppMetadata(appID: String) async throws -> Date? {
        let recordID = CKRecord.ID(recordName: "app_\(appID)")

        do {
            let record = try await privateDatabase.record(for: recordID)
            return record["lastCheckedDate"] as? Date
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// 모든 앱 메타데이터 불러오기
    func fetchAllAppMetadata() async throws -> [String: Date] {
        let query = CKQuery(recordType: appMetadataRecordType, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)

        var metadata: [String: Date] = [:]

        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                if let appID = record["appID"] as? String,
                   let lastCheckedDate = record["lastCheckedDate"] as? Date {
                    metadata[appID] = lastCheckedDate
                }
            case .failure:
                continue
            }
        }

        return metadata
    }

    // MARK: - Apps Sync

    /// 앱 정보 저장
    func saveApp(_ app: AppInfo) async throws {
        let recordID = CKRecord.ID(recordName: "app_\(app.id)")
        let record = CKRecord(recordType: appRecordType, recordID: recordID)

        record["appID"] = app.id as CKRecordValue
        record["name"] = app.name as CKRecordValue
        record["bundleID"] = app.bundleID as CKRecordValue
        record["sku"] = app.sku as CKRecordValue
        record["iconURL"] = (app.iconURL ?? "") as CKRecordValue
        record["lastSynced"] = Date() as CKRecordValue

        try await privateDatabase.save(record)
    }

    /// 앱 목록 가져오기
    func fetchApps() async throws -> [AppInfo] {
        let query = CKQuery(recordType: appRecordType, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)

        var apps: [AppInfo] = []

        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                guard let appID = record["appID"] as? String,
                      let name = record["name"] as? String,
                      let bundleID = record["bundleID"] as? String,
                      let sku = record["sku"] as? String else {
                    continue
                }

                let iconURL = record["iconURL"] as? String

                let app = AppInfo(
                    id: appID,
                    name: name,
                    bundleID: bundleID,
                    sku: sku,
                    iconURL: iconURL?.isEmpty == true ? nil : iconURL
                )
                apps.append(app)
            case .failure:
                continue
            }
        }

        return apps
    }

    // MARK: - Reviews Sync

    /// 리뷰 저장
    func saveReview(_ review: CustomerReview, appID: String) async throws {
        let recordID = CKRecord.ID(recordName: "review_\(review.id)")
        let record = CKRecord(recordType: reviewRecordType, recordID: recordID)

        record["reviewID"] = review.id as CKRecordValue
        record["appID"] = appID as CKRecordValue
        record["rating"] = review.rating as CKRecordValue
        record["title"] = (review.title ?? "") as CKRecordValue
        record["body"] = (review.body ?? "") as CKRecordValue
        record["reviewerNickname"] = (review.reviewerNickname ?? "") as CKRecordValue
        record["createdDate"] = review.createdDate as CKRecordValue
        record["territory"] = review.territory as CKRecordValue
        record["lastSynced"] = Date() as CKRecordValue

        try await privateDatabase.save(record)

        // 응답이 있으면 저장
        if let response = review.response {
            try await saveReviewResponse(response, reviewID: review.id)
        }
    }

    /// 리뷰 응답 저장
    func saveReviewResponse(_ response: ReviewResponse, reviewID: String) async throws {
        let recordID = CKRecord.ID(recordName: "response_\(response.id)")
        let record = CKRecord(recordType: responseRecordType, recordID: recordID)

        record["responseID"] = response.id as CKRecordValue
        record["reviewID"] = reviewID as CKRecordValue
        record["responseBody"] = response.responseBody as CKRecordValue
        record["lastModifiedDate"] = response.lastModifiedDate as CKRecordValue
        record["state"] = response.state.rawValue as CKRecordValue

        try await privateDatabase.save(record)
    }

    /// 특정 앱의 리뷰 가져오기
    func fetchReviews(appID: String) async throws -> [CustomerReview] {
        let predicate = NSPredicate(format: "appID == %@", appID)
        let query = CKQuery(recordType: reviewRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]

        let results = try await privateDatabase.records(matching: query)

        var reviews: [CustomerReview] = []

        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                guard let reviewID = record["reviewID"] as? String,
                      let rating = record["rating"] as? Int,
                      let createdDate = record["createdDate"] as? Date,
                      let territory = record["territory"] as? String else {
                    continue
                }

                let title = record["title"] as? String
                let body = record["body"] as? String
                let reviewerNickname = record["reviewerNickname"] as? String

                // 응답 가져오기
                let response = try? await fetchReviewResponse(reviewID: reviewID)

                let review = CustomerReview(
                    id: reviewID,
                    rating: rating,
                    title: title?.isEmpty == true ? nil : title,
                    body: body?.isEmpty == true ? nil : body,
                    reviewerNickname: reviewerNickname?.isEmpty == true ? nil : reviewerNickname,
                    createdDate: createdDate,
                    territory: territory,
                    response: response
                )
                reviews.append(review)
            case .failure:
                continue
            }
        }

        return reviews
    }

    /// 리뷰 응답 가져오기
    func fetchReviewResponse(reviewID: String) async throws -> ReviewResponse? {
        let predicate = NSPredicate(format: "reviewID == %@", reviewID)
        let query = CKQuery(recordType: responseRecordType, predicate: predicate)

        let results = try await privateDatabase.records(matching: query)

        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                guard let responseID = record["responseID"] as? String,
                      let responseBody = record["responseBody"] as? String,
                      let lastModifiedDate = record["lastModifiedDate"] as? Date,
                      let stateString = record["state"] as? String,
                      let state = ReviewResponse.ResponseState(rawValue: stateString) else {
                    continue
                }

                return ReviewResponse(
                    id: responseID,
                    responseBody: responseBody,
                    lastModifiedDate: lastModifiedDate,
                    state: state
                )
            case .failure:
                continue
            }
        }

        return nil
    }

    // MARK: - iCloud Account Status

    /// iCloud 계정 상태 확인
    func checkAccountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }

    /// iCloud 사용 가능 여부 확인
    func isICloudAvailable() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}
