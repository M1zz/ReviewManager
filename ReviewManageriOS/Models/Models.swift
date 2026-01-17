//
//  Models.swift
//  ReviewManageriOS
//
//  CloudKit 데이터 모델
//

import Foundation
import CloudKit

// MARK: - AppInfo (CloudKit용)
struct AppInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let sku: String
    let primaryLocale: String
    var lastCheckedDate: Date?
    var newReviewsCount: Int
    var iconURL: String?

    init(
        id: String,
        name: String,
        bundleID: String,
        sku: String,
        primaryLocale: String = "en-US",
        lastCheckedDate: Date? = nil,
        newReviewsCount: Int = 0,
        iconURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.sku = sku
        self.primaryLocale = primaryLocale
        self.lastCheckedDate = lastCheckedDate
        self.newReviewsCount = newReviewsCount
        self.iconURL = iconURL
    }

    // CloudKit Record에서 생성
    init?(from record: CKRecord) {
        guard let appID = record["appID"] as? String,
              let name = record["name"] as? String,
              let bundleID = record["bundleID"] as? String,
              let sku = record["sku"] as? String else {
            return nil
        }

        self.id = appID
        self.name = name
        self.bundleID = bundleID
        self.sku = sku
        self.primaryLocale = record["primaryLocale"] as? String ?? "en-US"
        self.lastCheckedDate = record["lastCheckedDate"] as? Date
        self.newReviewsCount = record["newReviewsCount"] as? Int ?? 0
        self.iconURL = record["iconURL"] as? String
    }
}

// MARK: - CustomerReview (CloudKit용)
struct CustomerReview: Identifiable, Codable, Hashable {
    let id: String
    let rating: Int
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: Date
    let territory: String
    var response: ReviewResponse?

    init(
        id: String,
        rating: Int,
        title: String?,
        body: String?,
        reviewerNickname: String?,
        createdDate: Date,
        territory: String,
        response: ReviewResponse? = nil
    ) {
        self.id = id
        self.rating = rating
        self.title = title
        self.body = body
        self.reviewerNickname = reviewerNickname
        self.createdDate = createdDate
        self.territory = territory
        self.response = response
    }

    // CloudKit Record에서 생성
    init?(from record: CKRecord) {
        guard let reviewID = record["reviewID"] as? String,
              let rating = record["rating"] as? Int,
              let createdDate = record["createdDate"] as? Date,
              let territory = record["territory"] as? String else {
            return nil
        }

        self.id = reviewID
        self.rating = rating
        self.title = record["title"] as? String
        self.body = record["body"] as? String
        self.reviewerNickname = record["reviewerNickname"] as? String
        self.createdDate = createdDate
        self.territory = territory

        // Response 복원
        if let responseBody = record["responseBody"] as? String,
           let responseID = record["responseID"] as? String,
           let responseLastModifiedDate = record["responseLastModifiedDate"] as? Date,
           let responseState = record["responseState"] as? String,
           let state = ReviewResponse.State(rawValue: responseState) {
            self.response = ReviewResponse(
                id: responseID,
                responseBody: responseBody,
                lastModifiedDate: responseLastModifiedDate,
                state: state
            )
        } else {
            self.response = nil
        }
    }
}

// MARK: - ReviewResponse
struct ReviewResponse: Codable, Hashable {
    let id: String
    let responseBody: String
    let lastModifiedDate: Date
    let state: State

    enum State: String, Codable {
        case published = "PUBLISHED"
        case pending = "PENDING_PUBLISH"
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
