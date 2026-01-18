//
//  AppStoreConnectService.swift
//  ReviewManager
//
//  App Store Connect API 통신 서비스
//

import Foundation
import CryptoKit
import Compression
import zlib

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
    
    private func requestWithoutResponse(_ endpoint: String, method: String = "DELETE", body: Data? = nil) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let token = try generateJWT()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        print("📊 [APIService] 응답 상태 코드: \(httpResponse.statusCode)")

        if httpResponse.statusCode >= 400 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                let errorMessage = apiError.errors?.first?.detail ?? apiError.errors?.first?.title ?? "Unknown error"
                throw ServiceError.apiError(httpResponse.statusCode, errorMessage)
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        // 성공 응답 로깅
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            print("✅ [APIService] 요청 성공 (상태 코드: \(httpResponse.statusCode))")
        }
    }
    
    // MARK: - Apps
    func fetchApps() async throws -> [AppInfo] {
        let response: AppsResponse = try await request("/apps?limit=200")

        var apps: [AppInfo] = []

        for appData in response.data {
            var app = AppInfo(
                id: appData.id,
                name: appData.attributes.name,
                bundleID: appData.attributes.bundleId,
                sku: appData.attributes.sku ?? "",
                primaryLocale: appData.attributes.primaryLocale ?? "en-US"
            )

            // 각 앱의 버전 정보 가져오기
            do {
                let versionInfo = try await fetchLatestAppStoreVersion(appID: appData.id)
                app.currentVersion = versionInfo.version
                app.versionState = versionInfo.state
                print("✅ [\(app.name)] 버전 정보: v\(versionInfo.version) - \(versionInfo.state.displayName)")
            } catch {
                print("⚠️ [\(app.name)] 버전 정보 가져오기 실패: \(error.localizedDescription)")
            }

            apps.append(app)
        }

        return apps
    }

    // MARK: - App Store Version
    private func fetchLatestAppStoreVersion(appID: String) async throws -> (version: String, state: AppVersionState) {
        print("🔍 앱 버전 조회 시작: \(appID)")

        do {
            let response: AppStoreVersionsResponse = try await request("/apps/\(appID)/appStoreVersions?limit=1&sort=-createdDate")
            print("📡 API 응답 받음, 데이터 개수: \(response.data.count)")

            guard let latestVersion = response.data.first else {
                print("❌ 버전 데이터 없음 - 앱에 등록된 버전이 없을 수 있습니다")
                throw ServiceError.noData
            }

            let versionString = latestVersion.attributes.versionString
            let stateRaw = latestVersion.attributes.appStoreState
            let state = AppVersionState(rawValue: stateRaw) ?? .readyForSale

            print("📦 버전: \(versionString), 상태: \(stateRaw)")
            return (versionString, state)
        } catch let error as ServiceError {
            print("❌ ServiceError: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ 예상치 못한 오류: \(error)")
            throw error
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
                        let state = ReviewResponse.ResponseState(rawValue: attrs.state) ?? .published

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
        print("🌐 [APIService] respondToReview 시작")
        print("   리뷰 ID: \(reviewID)")
        print("   응답 길이: \(response.count)")

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

        print("📤 [APIService] POST /customerReviewResponses 요청 전송")
        do {
            try await requestWithoutResponse("/customerReviewResponses", method: "POST", body: bodyData)
            print("✅ [APIService] 응답 전송 성공")
        } catch {
            print("❌ [APIService] 응답 전송 실패: \(error)")
            throw error
        }
    }
    
    func deleteResponse(responseID: String) async throws {
        try await requestWithoutResponse("/customerReviewResponses/\(responseID)")
    }

    // MARK: - Sales Reports
    func fetchSalesReport(vendorNumber: String, reportDate: Date) async throws -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: reportDate)

        // Sales Reports는 특별한 엔드포인트와 쿼리 파라미터를 사용
        let queryItems = [
            URLQueryItem(name: "filter[frequency]", value: "DAILY"),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[reportType]", value: "SALES"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[reportDate]", value: dateString)
        ]

        var urlComponents = URLComponents(string: "\(baseURL)/salesReports")!
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        print("🔍 Sales Report 요청: \(dateString), Vendor: \(vendorNumber)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        print("📡 Sales Report 응답: \(httpResponse.statusCode), 데이터 크기: \(data.count) bytes")

        if httpResponse.statusCode != 200 {
            // 에러 응답 로깅
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Sales Report 에러 응답: \(errorString)")
            }
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        // gzip 압축된 데이터 반환
        return data
    }

    // 최근 30일 다운로드 수 가져오기
    func fetch30DaysDownloads(vendorNumber: String) async throws -> Int {
        print("📊 최근 30일 다운로드 수 가져오기 시작")

        var totalDownloads = 0
        let calendar = Calendar.current
        let today = Date()

        // 최근 30일 동안 반복
        for daysAgo in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                continue
            }

            do {
                let data = try await fetchSalesReport(vendorNumber: vendorNumber, reportDate: date)
                let downloads = try parseSalesReportTSV(data)
                totalDownloads += downloads

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                print("  📅 \(dateFormatter.string(from: date)): \(downloads) downloads")
            } catch {
                // 데이터가 없는 날은 스킵 (에러 무시)
                if let serviceError = error as? ServiceError,
                   case ServiceError.httpError(let code) = serviceError, code == 400 {
                    // 400 에러는 데이터가 없는 날
                    continue
                }
                print("  ⚠️ \(date): \(error.localizedDescription)")
            }

            // API rate limit 방지를 위해 약간의 지연
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1초
        }

        print("✅ 30일 총 다운로드: \(totalDownloads)")
        return totalDownloads
    }

    // TSV 파일 파싱
    func parseSalesReportTSV(_ data: Data) throws -> Int {
        // gzip 압축 해제
        guard let decompressedData = decompressGzip(data) else {
            print("❌ gzip 압축 해제 실패")
            throw ServiceError.invalidData
        }

        guard let tsvString = String(data: decompressedData, encoding: .utf8) else {
            print("❌ TSV 문자열 변환 실패")
            throw ServiceError.invalidData
        }

        // TSV 파싱: 탭으로 구분된 데이터
        let lines = tsvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return 0
        }

        // 헤더 줄 확인
        let header = lines[0].components(separatedBy: "\t")

        // Units 컬럼 인덱스 찾기
        guard let unitsIndex = header.firstIndex(of: "Units") else {
            return 0
        }

        var totalDownloads = 0

        // 데이터 행 파싱
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let columns = line.components(separatedBy: "\t")
            guard columns.count > unitsIndex else { continue }

            if let units = Int(columns[unitsIndex]) {
                totalDownloads += units
            }
        }

        return totalDownloads
    }

    // MARK: - Gzip Decompression
    private func decompressGzip(_ data: Data) -> Data? {
        return data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Data? in
            guard let baseAddress = ptr.baseAddress else { return nil }

            var stream = z_stream()
            stream.avail_in = UInt32(data.count)
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))

            // 16 + MAX_WBITS는 gzip 형식을 의미
            guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }

            defer { inflateEnd(&stream) }

            var decompressed = Data()
            let bufferSize = 32768
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            repeat {
                stream.avail_out = UInt32(bufferSize)

                let status = buffer.withUnsafeMutableBytes { bufferPtr in
                    stream.next_out = bufferPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }

                guard status == Z_OK || status == Z_STREAM_END else {
                    return nil
                }

                let bytesProcessed = bufferSize - Int(stream.avail_out)
                decompressed.append(buffer, count: bytesProcessed)

                if status == Z_STREAM_END {
                    break
                }
            } while stream.avail_out == 0

            return decompressed
        }
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
    case noData
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
        case .noData:
            return "데이터가 없습니다."
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
