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
    private let userSettingsRecordType = "UserSettings"

    private init() {
        // iOS와 동일한 컨테이너 사용
        container = CKContainer(identifier: "iCloud.com.ysoup.ReviewManager")
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - API Credentials Sync

    /// API 인증 정보를 CloudKit에 저장
    func saveCredentials(issuerID: String, keyID: String, privateKey: String) async throws {
        print("📤 [CloudKit] Credentials 저장 시작 (컨테이너: iCloud.com.ysoup.ReviewManager)")

        let recordID = CKRecord.ID(recordName: "credentials")

        // 기존 레코드 가져오기 시도
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
            print("✅ [CloudKit] 기존 credentials 레코드 발견, 업데이트")
        } catch {
            // 없으면 새로 생성
            record = CKRecord(recordType: credentialsRecordType, recordID: recordID)
            print("📝 [CloudKit] 새 credentials 레코드 생성")
        }

        record["issuerID"] = issuerID as CKRecordValue
        record["keyID"] = keyID as CKRecordValue
        record["privateKey"] = privateKey as CKRecordValue
        record["lastModified"] = Date() as CKRecordValue

        // .changedKeys 정책으로 저장
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("✅ [CloudKit] Credentials 저장 완료!")
                    continuation.resume()
                case .failure(let error):
                    print("❌ [CloudKit] Credentials 저장 실패: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
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

        // 기존 레코드 가져오기 시도
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            // 없으면 새로 생성
            record = CKRecord(recordType: appMetadataRecordType, recordID: recordID)
        }

        record["appID"] = appID as CKRecordValue
        record["lastCheckedDate"] = lastCheckedDate as CKRecordValue

        // .changedKeys 정책으로 저장
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
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

        // 기존 레코드 가져오기 시도
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            // 없으면 새로 생성
            record = CKRecord(recordType: appRecordType, recordID: recordID)
        }

        record["appID"] = app.id as CKRecordValue
        record["name"] = app.name as CKRecordValue
        record["bundleID"] = app.bundleID as CKRecordValue
        record["sku"] = app.sku as CKRecordValue
        record["iconURL"] = (app.iconURL ?? "") as CKRecordValue
        record["currentVersion"] = (app.currentVersion ?? "") as CKRecordValue
        record["versionState"] = (app.versionState?.rawValue ?? "") as CKRecordValue
        record["lastSynced"] = Date() as CKRecordValue

        // .changedKeys 정책으로 저장
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
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

        // 기존 레코드 가져오기 시도
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            // 없으면 새로 생성
            record = CKRecord(recordType: reviewRecordType, recordID: recordID)
        }

        record["reviewID"] = review.id as CKRecordValue
        record["appID"] = appID as CKRecordValue
        record["rating"] = review.rating as CKRecordValue
        record["title"] = (review.title ?? "") as CKRecordValue
        record["body"] = (review.body ?? "") as CKRecordValue
        record["reviewerNickname"] = (review.reviewerNickname ?? "") as CKRecordValue
        record["createdDate"] = review.createdDate as CKRecordValue
        record["territory"] = review.territory as CKRecordValue
        record["lastSynced"] = Date() as CKRecordValue

        // 응답 정보도 리뷰 레코드에 함께 저장 (iOS 호환성)
        if let response = review.response {
            record["responseID"] = response.id as CKRecordValue
            record["responseBody"] = response.responseBody as CKRecordValue
            record["responseLastModifiedDate"] = response.lastModifiedDate as CKRecordValue
            record["responseState"] = response.state.rawValue as CKRecordValue
        } else {
            // 응답이 없으면 필드 제거
            record["responseID"] = nil
            record["responseBody"] = nil
            record["responseLastModifiedDate"] = nil
            record["responseState"] = nil
        }

        // .changedKeys 정책으로 저장
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
    }

    /// 리뷰 응답 저장
    func saveReviewResponse(_ response: ReviewResponse, reviewID: String) async throws {
        let recordID = CKRecord.ID(recordName: "response_\(response.id)")

        // 기존 레코드 가져오기 시도
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            // 없으면 새로 생성
            record = CKRecord(recordType: responseRecordType, recordID: recordID)
        }

        record["responseID"] = response.id as CKRecordValue
        record["reviewID"] = reviewID as CKRecordValue
        record["responseBody"] = response.responseBody as CKRecordValue
        record["lastModifiedDate"] = response.lastModifiedDate as CKRecordValue
        record["state"] = response.state.rawValue as CKRecordValue

        // .changedKeys 정책으로 저장
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
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

    // MARK: - CloudKit Data Management

    /// CloudKit의 모든 데이터 삭제 (디버깅용)
    func deleteAllCloudKitData() async throws {
        print("🗑️ CloudKit 데이터 삭제 시작...")

        // 1. 모든 App 레코드 삭제
        do {
            let appQuery = CKQuery(recordType: appRecordType, predicate: NSPredicate(value: true))
            let appResults = try await privateDatabase.records(matching: appQuery)

            for (recordID, result) in appResults.matchResults {
                if case .success = result {
                    try await privateDatabase.deleteRecord(withID: recordID)
                }
            }
            print("✅ App 레코드 삭제 완료")
        } catch {
            print("⚠️ App 레코드 삭제 실패: \(error.localizedDescription)")
        }

        // 2. 모든 Review 레코드 삭제
        do {
            let reviewQuery = CKQuery(recordType: reviewRecordType, predicate: NSPredicate(value: true))
            let reviewResults = try await privateDatabase.records(matching: reviewQuery)

            for (recordID, result) in reviewResults.matchResults {
                if case .success = result {
                    try await privateDatabase.deleteRecord(withID: recordID)
                }
            }
            print("✅ Review 레코드 삭제 완료")
        } catch {
            print("⚠️ Review 레코드 삭제 실패: \(error.localizedDescription)")
        }

        // 3. 모든 ReviewResponse 레코드 삭제
        do {
            let responseQuery = CKQuery(recordType: responseRecordType, predicate: NSPredicate(value: true))
            let responseResults = try await privateDatabase.records(matching: responseQuery)

            for (recordID, result) in responseResults.matchResults {
                if case .success = result {
                    try await privateDatabase.deleteRecord(withID: recordID)
                }
            }
            print("✅ ReviewResponse 레코드 삭제 완료")
        } catch {
            print("⚠️ ReviewResponse 레코드 삭제 실패: \(error.localizedDescription)")
        }

        // 4. 모든 Metadata 레코드 삭제
        do {
            let metadataQuery = CKQuery(recordType: appMetadataRecordType, predicate: NSPredicate(value: true))
            let metadataResults = try await privateDatabase.records(matching: metadataQuery)

            for (recordID, result) in metadataResults.matchResults {
                if case .success = result {
                    try await privateDatabase.deleteRecord(withID: recordID)
                }
            }
            print("✅ Metadata 레코드 삭제 완료")
        } catch {
            print("⚠️ Metadata 레코드 삭제 실패: \(error.localizedDescription)")
        }

        print("✅ CloudKit 데이터 삭제 완료!")
    }

    // MARK: - User Settings Sync (Hidden Apps, App Order)

    /// 숨긴 앱 목록 저장
    func saveHiddenApps(_ hiddenAppIDs: Set<String>) async throws {
        let recordID = CKRecord.ID(recordName: "userSettings")

        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: userSettingsRecordType, recordID: recordID)
        }

        record["hiddenAppIDs"] = Array(hiddenAppIDs) as CKRecordValue
        record["lastModified"] = Date() as CKRecordValue

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
    }

    /// 숨긴 앱 목록 불러오기
    func fetchHiddenApps() async throws -> Set<String>? {
        let recordID = CKRecord.ID(recordName: "userSettings")

        do {
            let record = try await privateDatabase.record(for: recordID)
            guard let hiddenAppIDs = record["hiddenAppIDs"] as? [String] else {
                return nil
            }
            return Set(hiddenAppIDs)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// 앱 순서 저장
    func saveAppOrder(_ appOrder: [String]) async throws {
        let recordID = CKRecord.ID(recordName: "userSettings")

        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: userSettingsRecordType, recordID: recordID)
        }

        record["appOrder"] = appOrder as CKRecordValue
        record["lastModified"] = Date() as CKRecordValue

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.qualityOfService = .userInitiated
            privateDatabase.add(operation)
        }
    }

    /// 앱 순서 불러오기
    func fetchAppOrder() async throws -> [String]? {
        let recordID = CKRecord.ID(recordName: "userSettings")

        do {
            let record = try await privateDatabase.record(for: recordID)
            return record["appOrder"] as? [String]
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
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
