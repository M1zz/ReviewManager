//
//  Models.swift
//  ReviewManager
//
//  App Store Connect API 데이터 모델
//

import Foundation

// MARK: - App Info
struct AppInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let sku: String
    let primaryLocale: String
    var lastCheckedDate: Date?
    var newReviewsCount: Int
    var iconURL: String?
    var currentVersion: String?
    var versionState: AppVersionState?

    init(id: String, name: String, bundleID: String, sku: String = "", primaryLocale: String = "en-US", lastCheckedDate: Date? = nil, newReviewsCount: Int = 0, iconURL: String? = nil, currentVersion: String? = nil, versionState: AppVersionState? = nil) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.sku = sku
        self.primaryLocale = primaryLocale
        self.lastCheckedDate = lastCheckedDate
        self.newReviewsCount = newReviewsCount
        self.iconURL = iconURL
        self.currentVersion = currentVersion
        self.versionState = versionState
    }

    // Codable을 위한 커스텀 CodingKeys
    enum CodingKeys: String, CodingKey {
        case id, name, bundleID, sku, primaryLocale, lastCheckedDate, newReviewsCount, iconURL, currentVersion, versionState
    }

    // Decodable 구현 (API에서 받을 때)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        sku = try container.decode(String.self, forKey: .sku)
        primaryLocale = try container.decode(String.self, forKey: .primaryLocale)
        lastCheckedDate = try container.decodeIfPresent(Date.self, forKey: .lastCheckedDate)
        newReviewsCount = try container.decodeIfPresent(Int.self, forKey: .newReviewsCount) ?? 0
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        currentVersion = try container.decodeIfPresent(String.self, forKey: .currentVersion)
        versionState = try container.decodeIfPresent(AppVersionState.self, forKey: .versionState)
    }
}

// MARK: - App Version State
enum AppVersionState: String, Codable {
    case readyForSale = "READY_FOR_SALE"
    case processingForAppStore = "PROCESSING_FOR_APP_STORE"
    case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
    case inReview = "IN_REVIEW"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case rejected = "REJECTED"
    case metadataRejected = "METADATA_REJECTED"
    case removedFromSale = "REMOVED_FROM_SALE"
    case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
    case developerRejected = "DEVELOPER_REJECTED"
    case pendingAppleRelease = "PENDING_APPLE_RELEASE"
    case pendingContract = "PENDING_CONTRACT"
    case invalidBinary = "INVALID_BINARY"
    case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
    case replacedWithNewVersion = "REPLACED_WITH_NEW_VERSION"
    case preorderReadyForSale = "PREORDER_READY_FOR_SALE"

    var displayName: String {
        switch self {
        case .readyForSale:
            return "출시 중"
        case .processingForAppStore:
            return "처리 중"
        case .pendingDeveloperRelease:
            return "개발자 출시 대기"
        case .inReview:
            return "심사 중"
        case .waitingForReview:
            return "심사 대기 중"
        case .prepareForSubmission:
            return "제출 준비 중"
        case .rejected:
            return "거부됨"
        case .metadataRejected:
            return "메타데이터 거부됨"
        case .removedFromSale:
            return "판매 중지"
        case .developerRemovedFromSale:
            return "개발자가 판매 중지"
        case .developerRejected:
            return "개발자가 거부"
        case .pendingAppleRelease:
            return "Apple 출시 대기"
        case .pendingContract:
            return "계약 대기 중"
        case .invalidBinary:
            return "잘못된 바이너리"
        case .waitingForExportCompliance:
            return "수출 규정 대기"
        case .replacedWithNewVersion:
            return "새 버전으로 교체됨"
        case .preorderReadyForSale:
            return "사전 주문 가능"
        }
    }

    var badgeColor: String {
        switch self {
        case .readyForSale, .preorderReadyForSale:
            return "green"
        case .inReview, .waitingForReview, .processingForAppStore:
            return "blue"
        case .prepareForSubmission, .pendingDeveloperRelease, .pendingAppleRelease, .waitingForExportCompliance:
            return "orange"
        case .rejected, .metadataRejected, .invalidBinary, .removedFromSale, .developerRemovedFromSale, .developerRejected:
            return "red"
        case .pendingContract, .replacedWithNewVersion:
            return "gray"
        }
    }
}

// MARK: - Customer Review
struct CustomerReview: Identifiable, Codable {
    let id: String
    let rating: Int
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: Date
    let territory: String
    var response: ReviewResponse?
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: createdDate) + " (UTC)"
    }
    
    var starsDisplay: String {
        String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
    }
    
    var ratingColor: String {
        switch rating {
        case 5: return "green"
        case 4: return "blue"
        case 3: return "yellow"
        case 2: return "orange"
        default: return "red"
        }
    }
}

// MARK: - Review Response
struct ReviewResponse: Identifiable, Codable {
    let id: String
    let responseBody: String
    let lastModifiedDate: Date
    let state: ResponseState
    
    enum ResponseState: String, Codable {
        case pendingPublish = "PENDING_PUBLISH"
        case published = "PUBLISHED"
        
        var displayName: String {
            switch self {
            case .pendingPublish: return "게시 대기중"
            case .published: return "게시됨"
            }
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: lastModifiedDate) + " (UTC)"
    }
}

// MARK: - API Response Structures
struct AppsResponse: Codable {
    let data: [AppData]
    let links: PageLinks?
}

struct AppData: Codable {
    let type: String
    let id: String
    let attributes: AppAttributes
}

struct AppAttributes: Codable {
    let name: String
    let bundleId: String
    let sku: String?
    let primaryLocale: String?
}

struct ReviewsResponse: Codable {
    let data: [ReviewData]
    let included: [IncludedData]?
    let links: PageLinks?
}

struct ReviewData: Codable {
    let type: String
    let id: String
    let attributes: ReviewAttributes
    let relationships: ReviewRelationships?
}

struct ReviewAttributes: Codable {
    let rating: Int
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: String
    let territory: String
}

struct ReviewRelationships: Codable {
    let response: ResponseRelationship?
}

struct ResponseRelationship: Codable {
    let data: RelationshipData?
}

struct RelationshipData: Codable {
    let type: String
    let id: String
}

struct IncludedData: Codable {
    let type: String
    let id: String
    let attributes: ResponseAttributes?
}

struct ResponseAttributes: Codable {
    let responseBody: String
    let lastModifiedDate: String
    let state: String
}

struct PageLinks: Codable {
    let next: String?
    let `self`: String
}

// MARK: - App Store Version Response
struct AppStoreVersionsResponse: Codable {
    let data: [AppStoreVersionData]
}

struct AppStoreVersionData: Codable {
    let id: String
    let type: String
    let attributes: AppStoreVersionAttributes
}

struct AppStoreVersionAttributes: Codable {
    let versionString: String
    let appStoreState: String
}

// MARK: - Request Bodies
struct CreateResponseRequest: Codable {
    let data: CreateResponseData
}

struct CreateResponseData: Codable {
    let type: String
    let attributes: CreateResponseAttributes
    let relationships: CreateResponseRelationships
}

struct CreateResponseAttributes: Codable {
    let responseBody: String
}

struct CreateResponseRelationships: Codable {
    let review: ReviewRelationshipData
}

struct ReviewRelationshipData: Codable {
    let data: RelationshipData
}

// MARK: - Error Response
struct APIError: Codable, Error {
    let errors: [ErrorDetail]?
}

struct ErrorDetail: Codable {
    let status: String
    let code: String
    let title: String
    let detail: String?
}

// MARK: - Filter Options
enum ReviewFilter: String, CaseIterable {
    case all = "전체"
    case withResponse = "응답 완료"
    case withoutResponse = "응답 대기"
    case fiveStars = "★★★★★"
    case fourStars = "★★★★☆"
    case threeStars = "★★★☆☆"
    case twoStars = "★★☆☆☆"
    case oneStar = "★☆☆☆☆"
    
    func matches(_ review: CustomerReview) -> Bool {
        switch self {
        case .all:
            return true
        case .withResponse:
            return review.response != nil
        case .withoutResponse:
            return review.response == nil
        case .fiveStars:
            return review.rating == 5
        case .fourStars:
            return review.rating == 4
        case .threeStars:
            return review.rating == 3
        case .twoStars:
            return review.rating == 2
        case .oneStar:
            return review.rating == 1
        }
    }
}

enum SortOption: String, CaseIterable {
    case newest = "최신순"
    case oldest = "오래된순"
    case highestRating = "높은 평점순"
    case lowestRating = "낮은 평점순"
    
    func sort(_ reviews: [CustomerReview]) -> [CustomerReview] {
        switch self {
        case .newest:
            return reviews.sorted { $0.createdDate > $1.createdDate }
        case .oldest:
            return reviews.sorted { $0.createdDate < $1.createdDate }
        case .highestRating:
            return reviews.sorted { $0.rating > $1.rating }
        case .lowestRating:
            return reviews.sorted { $0.rating < $1.rating }
        }
    }
}
