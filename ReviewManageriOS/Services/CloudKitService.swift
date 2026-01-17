//
//  CloudKitService.swift
//  ReviewManageriOS
//
//  CloudKit 읽기 전용 서비스
//

import Foundation
import CloudKit

class CloudKitService {
    static let shared = CloudKitService()

    private let container = CKContainer(identifier: "iCloud.com.ysoup.ReviewManager")
    private lazy var privateDatabase = container.privateCloudDatabase
    private let appRecordType = "App"
    private let reviewRecordType = "Review"
    private let credentialsRecordType = "APICredentials"

    private init() {}

    // MARK: - 앱 목록 가져오기
    func fetchApps() async throws -> [AppInfo] {
        let query = CKQuery(recordType: appRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let result = try await privateDatabase.records(matching: query)
            let apps = result.matchResults.compactMap { (_, result) -> AppInfo? in
                guard case .success(let record) = result else { return nil }
                return AppInfo(from: record)
            }
            return apps
        } catch let error as CKError {
            // 레코드 타입이 없는 경우 빈 배열 반환
            if error.code == .unknownItem {
                print("⚠️ CloudKit: 'App' 레코드 타입이 없습니다. macOS 앱에서 먼저 리뷰를 조회해주세요.")
                return []
            }
            print("❌ CloudKit 앱 가져오기 실패: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ CloudKit 앱 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - 리뷰 가져오기
    func fetchReviews(appID: String) async throws -> [CustomerReview] {
        let predicate = NSPredicate(format: "appID == %@", appID)
        let query = CKQuery(recordType: reviewRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]

        do {
            let result = try await privateDatabase.records(matching: query)
            let reviews = result.matchResults.compactMap { (_, result) -> CustomerReview? in
                guard case .success(let record) = result else { return nil }
                return CustomerReview(from: record)
            }
            return reviews
        } catch {
            print("❌ CloudKit 리뷰 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - API Credentials
    func fetchCredentials() async throws -> (issuerID: String, keyID: String, privateKey: String)? {
        let recordID = CKRecord.ID(recordName: "credentials")

        do {
            let record = try await privateDatabase.record(for: recordID)

            guard let issuerID = record["issuerID"] as? String,
                  let keyID = record["keyID"] as? String,
                  let privateKey = record["privateKey"] as? String else {
                print("⚠️ CloudKit: 인증 정보 필드가 없습니다")
                return nil
            }

            return (issuerID, keyID, privateKey)
        } catch let error as CKError where error.code == .unknownItem {
            // 레코드가 없으면 nil 반환
            print("⚠️ CloudKit: 인증 정보가 없습니다. macOS 앱에서 API 키를 설정해주세요.")
            return nil
        } catch {
            print("❌ CloudKit 인증 정보 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }
}
