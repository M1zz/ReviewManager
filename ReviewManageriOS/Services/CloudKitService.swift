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
        // sortDescriptors 제거 - 클라이언트에서 정렬

        do {
            let result = try await privateDatabase.records(matching: query)
            let apps = result.matchResults.compactMap { (_, result) -> AppInfo? in
                guard case .success(let record) = result else { return nil }
                return AppInfo(from: record)
            }
            // 클라이언트에서 이름순 정렬
            return apps.sorted { $0.name < $1.name }
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
        // appID 필터 제거 (Queryable Index 불필요) - 모든 리뷰 가져오기
        let query = CKQuery(recordType: reviewRecordType, predicate: NSPredicate(value: true))

        do {
            let result = try await privateDatabase.records(matching: query)
            let reviews = result.matchResults.compactMap { (_, result) -> CustomerReview? in
                guard case .success(let record) = result else { return nil }
                return CustomerReview(from: record)
            }
            // 클라이언트에서 appID 필터링 후 날짜순 정렬 (최신순)
            return reviews
                .filter { $0.appID == appID }
                .sorted { $0.createdDate > $1.createdDate }
        } catch {
            print("❌ CloudKit 리뷰 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - API Credentials
    func fetchCredentials() async throws -> (issuerID: String, keyID: String, privateKey: String)? {
        print("📥 [iOS CloudKit] Credentials 가져오기 시작 (컨테이너: iCloud.com.ysoup.ReviewManager)")

        let recordID = CKRecord.ID(recordName: "credentials")

        do {
            let record = try await privateDatabase.record(for: recordID)
            print("✅ [iOS CloudKit] Credentials 레코드 발견")

            guard let issuerID = record["issuerID"] as? String,
                  let keyID = record["keyID"] as? String,
                  let privateKey = record["privateKey"] as? String else {
                print("⚠️ [iOS CloudKit] 인증 정보 필드가 없습니다")
                return nil
            }

            print("✅ [iOS CloudKit] Credentials 로드 성공")
            return (issuerID, keyID, privateKey)
        } catch let error as CKError where error.code == .unknownItem {
            // 레코드가 없으면 nil 반환
            print("⚠️ [iOS CloudKit] 인증 정보가 없습니다. macOS 앱에서 API 키를 설정 → 저장해주세요.")
            print("   💡 macOS: 설정 → API → 편집 → 저장")
            return nil
        } catch {
            print("❌ [iOS CloudKit] 인증 정보 가져오기 실패: \(error.localizedDescription)")
            throw error
        }
    }
}
