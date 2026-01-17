//
//  CoreDataModels.swift
//  ReviewManager iOS
//
//  CoreData 모델 (코드 기반)
//

import Foundation
import CoreData

// MARK: - App Entity
@objc(AppEntity)
public class AppEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var bundleID: String
    @NSManaged public var sku: String
    @NSManaged public var iconURL: String?
    @NSManaged public var lastSynced: Date?
    @NSManaged public var reviews: NSSet?
}

extension AppEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppEntity> {
        return NSFetchRequest<AppEntity>(entityName: "AppEntity")
    }

    var reviewsArray: [ReviewEntity] {
        let set = reviews as? Set<ReviewEntity> ?? []
        return set.sorted { $0.createdDate > $1.createdDate }
    }

    func toAppInfo() -> AppInfo {
        return AppInfo(
            id: id,
            name: name,
            bundleID: bundleID,
            sku: sku,
            iconURL: iconURL
        )
    }
}

// MARK: - Review Entity
@objc(ReviewEntity)
public class ReviewEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var rating: Int16
    @NSManaged public var title: String?
    @NSManaged public var body: String?
    @NSManaged public var reviewerNickname: String?
    @NSManaged public var createdDate: Date
    @NSManaged public var territory: String
    @NSManaged public var app: AppEntity?
    @NSManaged public var response: ResponseEntity?
}

extension ReviewEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ReviewEntity> {
        return NSFetchRequest<ReviewEntity>(entityName: "ReviewEntity")
    }

    func toCustomerReview() -> CustomerReview {
        return CustomerReview(
            id: id,
            rating: Int(rating),
            title: title,
            body: body,
            reviewerNickname: reviewerNickname,
            createdDate: createdDate,
            territory: territory,
            response: response?.toReviewResponse()
        )
    }
}

// MARK: - Response Entity
@objc(ResponseEntity)
public class ResponseEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var responseBody: String
    @NSManaged public var lastModifiedDate: Date
    @NSManaged public var state: String
    @NSManaged public var review: ReviewEntity?
}

extension ResponseEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ResponseEntity> {
        return NSFetchRequest<ResponseEntity>(entityName: "ResponseEntity")
    }

    func toReviewResponse() -> ReviewResponse {
        let responseState = ReviewResponse.ResponseState(rawValue: state) ?? .published
        return ReviewResponse(
            id: id,
            responseBody: responseBody,
            lastModifiedDate: lastModifiedDate,
            state: responseState
        )
    }
}
