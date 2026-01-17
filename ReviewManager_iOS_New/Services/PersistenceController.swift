//
//  PersistenceController.swift
//  ReviewManager iOS
//
//  CoreData 영구 저장소 관리
//

import Foundation
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ReviewManager")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // 코드 기반 모델 설정
        let model = NSManagedObjectModel()

        // App Entity
        let appEntity = NSEntityDescription()
        appEntity.name = "AppEntity"
        appEntity.managedObjectClassName = "AppEntity"

        let appId = NSAttributeDescription()
        appId.name = "id"
        appId.attributeType = .stringAttributeType
        appId.isOptional = false

        let appName = NSAttributeDescription()
        appName.name = "name"
        appName.attributeType = .stringAttributeType
        appName.isOptional = false

        let appBundleID = NSAttributeDescription()
        appBundleID.name = "bundleID"
        appBundleID.attributeType = .stringAttributeType
        appBundleID.isOptional = false

        let appSku = NSAttributeDescription()
        appSku.name = "sku"
        appSku.attributeType = .stringAttributeType
        appSku.isOptional = false

        let appIconURL = NSAttributeDescription()
        appIconURL.name = "iconURL"
        appIconURL.attributeType = .stringAttributeType
        appIconURL.isOptional = true

        let appLastSynced = NSAttributeDescription()
        appLastSynced.name = "lastSynced"
        appLastSynced.attributeType = .dateAttributeType
        appLastSynced.isOptional = true

        appEntity.properties = [appId, appName, appBundleID, appSku, appIconURL, appLastSynced]

        // Review Entity
        let reviewEntity = NSEntityDescription()
        reviewEntity.name = "ReviewEntity"
        reviewEntity.managedObjectClassName = "ReviewEntity"

        let reviewId = NSAttributeDescription()
        reviewId.name = "id"
        reviewId.attributeType = .stringAttributeType
        reviewId.isOptional = false

        let reviewRating = NSAttributeDescription()
        reviewRating.name = "rating"
        reviewRating.attributeType = .integer16AttributeType
        reviewRating.isOptional = false

        let reviewTitle = NSAttributeDescription()
        reviewTitle.name = "title"
        reviewTitle.attributeType = .stringAttributeType
        reviewTitle.isOptional = true

        let reviewBody = NSAttributeDescription()
        reviewBody.name = "body"
        reviewBody.attributeType = .stringAttributeType
        reviewBody.isOptional = true

        let reviewerNickname = NSAttributeDescription()
        reviewerNickname.name = "reviewerNickname"
        reviewerNickname.attributeType = .stringAttributeType
        reviewerNickname.isOptional = true

        let reviewCreatedDate = NSAttributeDescription()
        reviewCreatedDate.name = "createdDate"
        reviewCreatedDate.attributeType = .dateAttributeType
        reviewCreatedDate.isOptional = false

        let reviewTerritory = NSAttributeDescription()
        reviewTerritory.name = "territory"
        reviewTerritory.attributeType = .stringAttributeType
        reviewTerritory.isOptional = false

        reviewEntity.properties = [reviewId, reviewRating, reviewTitle, reviewBody, reviewerNickname, reviewCreatedDate, reviewTerritory]

        // Response Entity
        let responseEntity = NSEntityDescription()
        responseEntity.name = "ResponseEntity"
        responseEntity.managedObjectClassName = "ResponseEntity"

        let responseId = NSAttributeDescription()
        responseId.name = "id"
        responseId.attributeType = .stringAttributeType
        responseId.isOptional = false

        let responseBody = NSAttributeDescription()
        responseBody.name = "responseBody"
        responseBody.attributeType = .stringAttributeType
        responseBody.isOptional = false

        let responseLastModifiedDate = NSAttributeDescription()
        responseLastModifiedDate.name = "lastModifiedDate"
        responseLastModifiedDate.attributeType = .dateAttributeType
        responseLastModifiedDate.isOptional = false

        let responseState = NSAttributeDescription()
        responseState.name = "state"
        responseState.attributeType = .stringAttributeType
        responseState.isOptional = false

        responseEntity.properties = [responseId, responseBody, responseLastModifiedDate, responseState]

        // Relationships
        let appToReviews = NSRelationshipDescription()
        appToReviews.name = "reviews"
        appToReviews.destinationEntity = reviewEntity
        appToReviews.maxCount = 0 // to-many
        appToReviews.deleteRule = .cascadeDeleteRule

        let reviewToApp = NSRelationshipDescription()
        reviewToApp.name = "app"
        reviewToApp.destinationEntity = appEntity
        reviewToApp.maxCount = 1 // to-one
        reviewToApp.deleteRule = .nullifyDeleteRule

        appToReviews.inverseRelationship = reviewToApp
        reviewToApp.inverseRelationship = appToReviews

        appEntity.properties.append(appToReviews)
        reviewEntity.properties.append(reviewToApp)

        let reviewToResponse = NSRelationshipDescription()
        reviewToResponse.name = "response"
        reviewToResponse.destinationEntity = responseEntity
        reviewToResponse.maxCount = 1 // to-one
        reviewToResponse.deleteRule = .cascadeDeleteRule

        let responseToReview = NSRelationshipDescription()
        responseToReview.name = "review"
        responseToReview.destinationEntity = reviewEntity
        responseToReview.maxCount = 1 // to-one
        responseToReview.deleteRule = .nullifyDeleteRule

        reviewToResponse.inverseRelationship = responseToReview
        responseToReview.inverseRelationship = reviewToResponse

        reviewEntity.properties.append(reviewToResponse)
        responseEntity.properties.append(responseToReview)

        model.entities = [appEntity, reviewEntity, responseEntity]

        let containerWithModel = NSPersistentContainer(name: "ReviewManager", managedObjectModel: model)

        containerWithModel.loadPersistentStores { description, error in
            if let error = error {
                fatalError("CoreData 로드 실패: \(error)")
            }
        }

        self.container = containerWithModel
    }

    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("CoreData 저장 실패: \(error)")
            }
        }
    }
}
