//
//  CloudKitService.swift
//  ReviewManager
//
//  CloudKit 동기화 서비스
//

import Foundation
import CloudKit

enum CloudKitError: Error {
    case notConfigured
    case containerNotAvailable
}

class CloudKitService {
    static let shared = CloudKitService()

    private var container: CKContainer?
    private var privateDatabase: CKDatabase?
    private var isInitialized = false

    // Record Types
    private let credentialsRecordType = "APICredentials"
    private let appMetadataRecordType = "AppMetadata"
    private let appRecordType = "App"
    private let reviewRecordType = "Review"
    private let responseRecordType = "ReviewResponse"

    private init() {
        // 초기화를 지연시킴 - iCloud 설정이 없으면 앱이 죽지 않도록
    }

    private func ensureInitialized() throws {
        guard !isInitialized else { return }

        do {
            container = CKContainer(identifier: "iCloud.com.ysoup.ReviewManager")
            privateDatabase = container?.privateCloudDatabase
            isInitialized = true
        } catch {
            throw CloudKitError.containerNotAvailable
        }
    }

    // MARK: - API Credentials Sync

    /// API 인증 정보를 CloudKit에 저장
    func saveCredentials(issuerID: String, keyID: String, privateKey: String) async throws {
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "credentials")

        // 기존 레코드 가져오기 시도
        let record: CKRecord

        do {
            let existingRecord = try await privateDatabase.record(for: recordID)

            // 타입이 다르면 삭제 후 재생성
            if existingRecord.recordType != credentialsRecordType {
                print("⚠️ 레코드 타입 불일치: \(existingRecord.recordType) → \(credentialsRecordType), 삭제 후 재생성")
                try await privateDatabase.deleteRecord(withID: recordID)
                try await Task.sleep(nanoseconds: 500_000_000)
                record = CKRecord(recordType: credentialsRecordType, recordID: recordID)
            } else {
                record = existingRecord
            }
        } catch {
            // 레코드가 없으면 새로 생성
            record = CKRecord(recordType: credentialsRecordType, recordID: recordID)
        }

        record["issuerID"] = issuerID as CKRecordValue
        record["keyID"] = keyID as CKRecordValue
        record["privateKey"] = privateKey as CKRecordValue
        record["lastModified"] = Date() as CKRecordValue

        // 저장 (항상 .changedKeys 정책 사용 - upsert 동작)
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

    /// CloudKit에서 API 인증 정보 불러오기
    func fetchCredentials() async throws -> (issuerID: String, keyID: String, privateKey: String)? {
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

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
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "credentials")
        try await privateDatabase.deleteRecord(withID: recordID)
    }

    // MARK: - App Metadata Sync

    /// 앱 메타데이터 (마지막 확인 시간) 저장
    func saveAppMetadata(appID: String, lastCheckedDate: Date) async throws {
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "appmeta_\(appID)")

        // 기존 레코드 가져오기 시도
        let record: CKRecord

        do {
            let existingRecord = try await privateDatabase.record(for: recordID)

            // 타입이 다르면 삭제 후 재생성
            if existingRecord.recordType != appMetadataRecordType {
                print("⚠️ 레코드 타입 불일치: \(existingRecord.recordType) → \(appMetadataRecordType), 삭제 후 재생성")
                try await privateDatabase.deleteRecord(withID: recordID)
                try await Task.sleep(nanoseconds: 500_000_000)
                record = CKRecord(recordType: appMetadataRecordType, recordID: recordID)
            } else {
                record = existingRecord
            }
        } catch {
            // 레코드가 없으면 새로 생성
            record = CKRecord(recordType: appMetadataRecordType, recordID: recordID)
        }

        record["appID"] = appID as CKRecordValue
        record["lastCheckedDate"] = lastCheckedDate as CKRecordValue

        // 저장 (항상 .changedKeys 정책 사용 - upsert 동작)
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
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "appmeta_\(appID)")

        do {
            let record = try await privateDatabase.record(for: recordID)
            return record["lastCheckedDate"] as? Date
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// 모든 앱 메타데이터 불러오기
    func fetchAllAppMetadata() async throws -> [String: Date] {
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

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
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "app_\(app.id)")

        // 기존 레코드 가져오기 시도
        let record: CKRecord

        do {
            let existingRecord = try await privateDatabase.record(for: recordID)

            // 타입이 다르면 삭제 후 재생성
            if existingRecord.recordType != appRecordType {
                print("⚠️ 레코드 타입 불일치: \(existingRecord.recordType) → \(appRecordType), 삭제 후 재생성")
                try await privateDatabase.deleteRecord(withID: recordID)
                try await Task.sleep(nanoseconds: 500_000_000)
                record = CKRecord(recordType: appRecordType, recordID: recordID)
            } else {
                record = existingRecord
            }
        } catch {
            // 레코드가 없으면 새로 생성
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

        // 저장 시도 (실패하면 재시도)
        var retryCount = 0
        let maxRetries = 3

        while retryCount < maxRetries {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let operation = CKModifyRecordsOperation(recordsToSave: [record])
                    operation.savePolicy = isNewRecord ? .allKeys : .changedKeys
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
                return // 성공하면 종료
            } catch let error as CKError where error.code == .serverRecordChanged {
                // 레코드가 서버에서 변경됨 - 다시 fetch하고 재시도
                print("⚠️ 서버 레코드 변경 감지, 재시도 중... (\(retryCount + 1)/\(maxRetries))")
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
                    // 최신 레코드 다시 fetch
                    if let freshRecord = try? await privateDatabase.record(for: recordID) {
                        record.setValuesForKeys(freshRecord.dictionaryWithValues(forKeys: Array(freshRecord.allKeys())))
                    }
                } else {
                    throw error
                }
            } catch {
                throw error
            }
        }
    }

    /// 앱 목록 가져오기
    func fetchApps() async throws -> [AppInfo] {
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

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
                let currentVersion = record["currentVersion"] as? String
                let versionStateRaw = record["versionState"] as? String

                var versionState: AppVersionState? = nil
                if let stateRaw = versionStateRaw, !stateRaw.isEmpty {
                    versionState = AppVersionState(rawValue: stateRaw)
                }

                let app = AppInfo(
                    id: appID,
                    name: name,
                    bundleID: bundleID,
                    sku: sku,
                    iconURL: iconURL?.isEmpty == true ? nil : iconURL,
                    currentVersion: currentVersion?.isEmpty == true ? nil : currentVersion,
                    versionState: versionState
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
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

        let recordID = CKRecord.ID(recordName: "review_\(review.id)")

        // 기존 레코드 가져오기 시도
        let record: CKRecord

        do {
            let existingRecord = try await privateDatabase.record(for: recordID)

            // 타입이 다르면 삭제 후 재생성
            if existingRecord.recordType != reviewRecordType {
                print("⚠️ 레코드 타입 불일치: \(existingRecord.recordType) → \(reviewRecordType), 삭제 후 재생성")
                try await privateDatabase.deleteRecord(withID: recordID)
                try await Task.sleep(nanoseconds: 500_000_000)
                record = CKRecord(recordType: reviewRecordType, recordID: recordID)
            } else {
                record = existingRecord
            }
        } catch {
            // 레코드가 없으면 새로 생성
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

        // 응답 정보를 직접 포함
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

        // 저장 (항상 .changedKeys 정책 사용 - upsert 동작)
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
        try ensureInitialized()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notConfigured
        }

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

                // 응답 복원
                var response: ReviewResponse?
                if let responseID = record["responseID"] as? String,
                   let responseBody = record["responseBody"] as? String,
                   let responseLastModifiedDate = record["responseLastModifiedDate"] as? Date,
                   let responseStateString = record["responseState"] as? String,
                   let responseState = ReviewResponse.ResponseState(rawValue: responseStateString) {
                    response = ReviewResponse(
                        id: responseID,
                        responseBody: responseBody,
                        lastModifiedDate: responseLastModifiedDate,
                        state: responseState
                    )
                }

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

    // MARK: - iCloud Account Status

    /// iCloud 계정 상태 확인
    func checkAccountStatus() async throws -> CKAccountStatus {
        try ensureInitialized()
        guard let container = container else {
            throw CloudKitError.notConfigured
        }
        return try await container.accountStatus()
    }

    /// iCloud 사용 가능 여부 확인
    func isICloudAvailable() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            print("⚠️ iCloud 사용 불가: \(error.localizedDescription)")
            return false
        }
    }
}
