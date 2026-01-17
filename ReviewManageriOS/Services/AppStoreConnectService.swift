//
//  AppStoreConnectService.swift
//  ReviewManager
//
//  App Store Connect API 통신 서비스
//

import Foundation
import CryptoKit

class AppStoreConnectService {
    private var issuerID: String = ""
    private var keyID: String = ""
    private var privateKey: String = ""
    
    private let baseURL = "https://api.appstoreconnect.apple.com/v1"
    
    func configure(issuerID: String, keyID: String, privateKey: String) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKey = privateKey
    }
    
    // MARK: - JWT Token Generation
    private func generateJWT() throws -> String {
        let header = JWTHeader(alg: "ES256", kid: keyID, typ: "JWT")
        
        let now = Date()
        let expiration = now.addingTimeInterval(20 * 60) // 20분
        
        let payload = JWTPayload(
            iss: issuerID,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(expiration.timeIntervalSince1970),
            aud: "appstoreconnect-v1"
        )
        
        let headerData = try JSONEncoder().encode(header)
        let payloadData = try JSONEncoder().encode(payload)
        
        let headerBase64 = headerData.base64URLEncodedString()
        let payloadBase64 = payloadData.base64URLEncodedString()
        
        let signatureInput = "\(headerBase64).\(payloadBase64)"
        
        let signature = try sign(message: signatureInput)
        
        return "\(signatureInput).\(signature)"
    }
    
    private func sign(message: String) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw ServiceError.invalidData
        }

        let cleanedKey = privateKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: cleanedKey) else {
            throw ServiceError.invalidPrivateKey
        }

        // Apple .p8 파일은 PKCS#8 DER 형식
        // 먼저 DER 형식으로 시도
        do {
            let p256Key = try P256.Signing.PrivateKey(derRepresentation: keyData)
            let signature = try p256Key.signature(for: messageData)
            return signature.rawRepresentation.base64URLEncodedString()
        } catch let derError {
            // DER 형식이 실패하면 raw 형식 시도 (32바이트)
            if keyData.count == 32 {
                do {
                    let p256Key = try P256.Signing.PrivateKey(rawRepresentation: keyData)
                    let signature = try p256Key.signature(for: messageData)
                    return signature.rawRepresentation.base64URLEncodedString()
                } catch {
                    throw ServiceError.signingFailed("Raw key error: \(error.localizedDescription)")
                }
            }

            // 모든 시도 실패
            throw ServiceError.signingFailed("DER 형식 오류: \(derError.localizedDescription). 키 길이: \(keyData.count) 바이트")
        }
    }
    
    // MARK: - Date Parsing
    private func parseDate(from dateString: String) -> Date {
        // ISO8601 표준 형식들을 순서대로 시도
        let formatters: [ISO8601DateFormatter] = [
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter
            }(),
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                return formatter
            }(),
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                return formatter
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                print("✅ 날짜 파싱 성공: \(dateString) -> \(date)")
                return date
            }
        }

        // 모든 시도 실패 시 경고 후 현재 시간 반환
        print("⚠️ 날짜 파싱 실패: \(dateString)")
        return Date()
    }

    // MARK: - API Requests
    private func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw ServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let token = try generateJWT()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                let errorMessage = apiError.errors?.first?.detail ?? apiError.errors?.first?.title ?? "Unknown error"
                throw ServiceError.apiError(httpResponse.statusCode, errorMessage)
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func requestWithoutResponse(_ endpoint: String, method: String = "DELETE") async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw ServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        let token = try generateJWT()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                let errorMessage = apiError.errors?.first?.detail ?? apiError.errors?.first?.title ?? "Unknown error"
                throw ServiceError.apiError(httpResponse.statusCode, errorMessage)
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Apps
    func fetchApps() async throws -> [AppInfo] {
        let response: AppsResponse = try await request("/apps?limit=200")
        
        return response.data.map { appData in
            AppInfo(
                id: appData.id,
                name: appData.attributes.name,
                bundleID: appData.attributes.bundleId,
                sku: appData.attributes.sku ?? "",
                primaryLocale: appData.attributes.primaryLocale ?? "en-US"
            )
        }
    }
    
    // MARK: - Reviews
    func fetchReviews(appID: String) async throws -> [CustomerReview] {
        var allReviews: [CustomerReview] = []
        var nextURL: String? = "/apps/\(appID)/customerReviews?limit=200&sort=-createdDate&include=response"
        
        while let url = nextURL {
            let response: ReviewsResponse = try await request(url)
            
            // 응답 데이터를 딕셔너리로 변환
            var responsesDict: [String: ReviewResponse] = [:]
            if let included = response.included {
                for item in included where item.type == "customerReviewResponses" {
                    if let attrs = item.attributes {
                        let date = parseDate(from: attrs.lastModifiedDate)
                        let state = ReviewResponse.State(rawValue: attrs.state) ?? .published

                        responsesDict[item.id] = ReviewResponse(
                            id: item.id,
                            responseBody: attrs.responseBody,
                            lastModifiedDate: date,
                            state: state
                        )
                    }
                }
            }

            let reviews = response.data.map { reviewData -> CustomerReview in
                let createdDate = parseDate(from: reviewData.attributes.createdDate)
                
                var reviewResponse: ReviewResponse? = nil
                if let responseRelationship = reviewData.relationships?.response?.data {
                    reviewResponse = responsesDict[responseRelationship.id]
                }
                
                return CustomerReview(
                    id: reviewData.id,
                    rating: reviewData.attributes.rating,
                    title: reviewData.attributes.title,
                    body: reviewData.attributes.body,
                    reviewerNickname: reviewData.attributes.reviewerNickname,
                    createdDate: createdDate,
                    territory: reviewData.attributes.territory,
                    response: reviewResponse
                )
            }
            
            allReviews.append(contentsOf: reviews)
            
            // 다음 페이지 확인
            if let next = response.links?.next {
                // baseURL 제거하고 경로만 추출
                nextURL = next.replacingOccurrences(of: "https://api.appstoreconnect.apple.com/v1", with: "")
            } else {
                nextURL = nil
            }
        }
        
        return allReviews
    }
    
    // MARK: - Responses
    func respondToReview(reviewID: String, response: String) async throws {
        let requestBody = CreateResponseRequest(
            data: CreateResponseData(
                type: "customerReviewResponses",
                attributes: CreateResponseAttributes(responseBody: response),
                relationships: CreateResponseRelationships(
                    review: ReviewRelationshipData(
                        data: RelationshipData(type: "customerReviews", id: reviewID)
                    )
                )
            )
        )
        
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)
        
        let _: IncludedData = try await request("/customerReviewResponses", method: "POST", body: bodyData)
    }
    
    func deleteResponse(responseID: String) async throws {
        try await requestWithoutResponse("/customerReviewResponses/\(responseID)")
    }
}

// MARK: - JWT Structures
private struct JWTHeader: Codable {
    let alg: String
    let kid: String
    let typ: String
}

private struct JWTPayload: Codable {
    let iss: String
    let iat: Int
    let exp: Int
    let aud: String
}

// MARK: - Service Errors
enum ServiceError: LocalizedError {
    case invalidURL
    case invalidData
    case invalidPrivateKey
    case signingFailed(String)
    case invalidResponse
    case httpError(Int)
    case apiError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidData:
            return "잘못된 데이터입니다."
        case .invalidPrivateKey:
            return "Private Key가 올바르지 않습니다. .p8 파일의 내용을 확인해주세요."
        case .signingFailed(let message):
            return "서명 실패: \(message)"
        case .invalidResponse:
            return "서버 응답이 올바르지 않습니다."
        case .httpError(let code):
            return "HTTP 오류: \(code)"
        case .apiError(let code, let message):
            return "API 오류 (\(code)): \(message)"
        }
    }
}

// MARK: - Base64URL Encoding
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
