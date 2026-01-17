//
//  LocalModels.swift
//  ReviewManageriOS
//
//  로컬 저장용 모델
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

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: createdDate) + " (UTC)"
    }

    var starsDisplay: String {
        let rating = Int(self.rating)
        return String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
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

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: lastModifiedDate) + " (UTC)"
    }

    var displayState: String {
        if state == "PUBLISHED" {
            return "게시됨"
        } else {
            return "게시 대기중"
        }
    }
}
