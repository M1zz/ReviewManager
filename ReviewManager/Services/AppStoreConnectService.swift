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

    // 최근 N일 Sales 데이터 가져오기 (상세 정보 포함)
    func fetchSalesData(vendorNumber: String, days: Int = 30) async throws -> SalesData {
        print("📊 최근 \(days)일 Sales 데이터 가져오기 시작")

        let calendar = Calendar.current
        let today = Date()

        // 날짜 목록 생성
        var dates: [Date] = []
        for daysAgo in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) {
                dates.append(date)
            }
        }

        return try await fetchSalesDataForDates(vendorNumber: vendorNumber, dates: dates)
    }

    // 특정 날짜 목록의 Sales 데이터 가져오기 (스마트 캐싱용)
    func fetchSalesDataForDates(vendorNumber: String, dates: [Date]) async throws -> SalesData {
        print("📊 \(dates.count)개 날짜의 Sales 데이터 가져오기 시작")

        var salesData = SalesData()
        var countryMap: [String: CountrySalesData] = [:]
        var dailyDataArray: [DailySalesData] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // 각 날짜별로 데이터 가져오기
        for date in dates {
            do {
                let data = try await fetchSalesReport(vendorNumber: vendorNumber, reportDate: date)
                let (units, revenue, countries) = try parseSalesReportDetailed(data)

                salesData.totalUnits += units
                salesData.totalRevenue += revenue

                // 일별 데이터 저장
                dailyDataArray.append(DailySalesData(date: date, units: units, revenue: revenue))

                // 국가별 데이터 집계
                for country in countries {
                    if let existing = countryMap[country.countryCode] {
                        countryMap[country.countryCode] = CountrySalesData(
                            countryCode: country.countryCode,
                            units: existing.units + country.units,
                            revenue: existing.revenue + country.revenue
                        )
                    } else {
                        countryMap[country.countryCode] = country
                    }
                }

                print("  📅 \(dateFormatter.string(from: date)): \(units) units, $\(String(format: "%.2f", revenue))")
            } catch {
                // 데이터가 없는 날은 스킵
                if let serviceError = error as? ServiceError,
                   case ServiceError.httpError(let code) = serviceError, code == 400 {
                    continue
                }
                print("  ⚠️ \(dateFormatter.string(from: date)): \(error.localizedDescription)")
            }

            // API rate limit 방지
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1초
        }

        salesData.countryData = Array(countryMap.values).sorted { $0.units > $1.units }
        salesData.dailyData = dailyDataArray.sorted { $0.date < $1.date }
        salesData.lastUpdated = Date()

        // 날짜 범위 설정
        if let earliest = dailyDataArray.map({ $0.date }).min() {
            salesData.earliestDate = earliest
        }
        if let latest = dailyDataArray.map({ $0.date }).max() {
            salesData.latestDate = latest
        }

        print("✅ \(dates.count)개 날짜 총 판매: \(salesData.totalUnits) units, $\(String(format: "%.2f", salesData.totalRevenue))")
        return salesData
    }

    // TSV 파일 파싱 (간단 버전 - Units만)
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

    // TSV 파일 파싱 (상세 버전 - Units, Revenue, Country)
    func parseSalesReportDetailed(_ data: Data) throws -> (units: Int, revenue: Double, countries: [CountrySalesData]) {
        // gzip 압축 해제
        guard let decompressedData = decompressGzip(data) else {
            print("❌ gzip 압축 해제 실패")
            throw ServiceError.invalidData
        }

        guard let tsvString = String(data: decompressedData, encoding: .utf8) else {
            print("❌ TSV 문자열 변환 실패")
            throw ServiceError.invalidData
        }

        // TSV 파싱
        let lines = tsvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return (0, 0.0, [])
        }

        let header = lines[0].components(separatedBy: "\t")

        // 필요한 컬럼 인덱스 찾기
        guard let unitsIndex = header.firstIndex(of: "Units"),
              let proceedsIndex = header.firstIndex(of: "Developer Proceeds"),
              let countryIndex = header.firstIndex(of: "Country Code") else {
            print("❌ 필요한 컬럼을 찾을 수 없음")
            return (0, 0.0, [])
        }

        // Product Type Identifier 인덱스 (선택적)
        let productTypeIndex = header.firstIndex(of: "Product Type Identifier")

        // 유효한 Product Type Identifiers (앱 다운로드만)
        // 1 = iOS 앱, 1F = iOS 유료 앱, F1 = iOS 무료 앱, 1E = 앱 번들
        // 7 = 업데이트 (제외), 1T = IAP (제외)
        let validProductTypes = Set(["1", "1F", "F1", "1E", "7F1"])

        var totalUnits = 0
        var totalRevenue = 0.0
        var countryMap: [String: (units: Int, revenue: Double)] = [:]

        // 데이터 행 파싱
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let columns = line.components(separatedBy: "\t")
            guard columns.count > max(unitsIndex, proceedsIndex, countryIndex) else { continue }

            // Product Type 확인 (있으면)
            if let ptIndex = productTypeIndex, columns.count > ptIndex {
                let productType = columns[ptIndex].trimmingCharacters(in: .whitespaces)
                // 업데이트(7) 제외
                if productType == "7" || productType == "1T" {
                    continue
                }
                // 유효한 타입이 아니고 비어있지도 않으면 스킵
                if !productType.isEmpty && !validProductTypes.contains(productType) && !productType.hasPrefix("F") && !productType.hasPrefix("1") {
                    continue
                }
            }

            let units = Int(columns[unitsIndex]) ?? 0
            let revenue = Double(columns[proceedsIndex]) ?? 0.0
            let countryCode = columns[countryIndex]

            // Units가 음수일 수 있음 (환불)
            totalUnits += units
            totalRevenue += revenue

            // 국가별 집계
            if let existing = countryMap[countryCode] {
                countryMap[countryCode] = (existing.units + units, existing.revenue + revenue)
            } else {
                countryMap[countryCode] = (units, revenue)
            }
        }

        let countries = countryMap.map { CountrySalesData(countryCode: $0.key, units: $0.value.units, revenue: $0.value.revenue) }

        return (totalUnits, totalRevenue, countries)
    }

    // MARK: - Analytics Reports API (올바른 워크플로우)

    /// 1. Analytics Report Request 생성 (ONGOING 타입)
    func createAnalyticsReportRequest(appID: String) async throws -> String {
        print("📊 [Analytics] 리포트 요청 생성 시작: \(appID)")

        let urlString = "\(baseURL)/analyticsReportRequests"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        // 요청 바디 생성
        let requestBody = AnalyticsReportRequestCreate(
            data: AnalyticsReportRequestCreateData(
                type: "analyticsReportRequests",
                attributes: AnalyticsReportRequestCreateAttributes(
                    accessType: "ONGOING"
                ),
                relationships: AnalyticsReportRequestRelationships(
                    app: AnalyticsAppRelationship(
                        data: AnalyticsAppData(
                            type: "apps",
                            id: appID
                        )
                    )
                )
            )
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 201 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        // 응답 파싱
        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnalyticsReportRequestResponse.self, from: data)

        let requestId = responseData.data.id
        print("✅ [Analytics] 리포트 요청 생성 완료: \(requestId)")
        print("⏳ [Analytics] 첫 리포트 생성까지 1-2일 소요됩니다")

        return requestId
    }

    /// 2. Analytics Report Request 상태 확인
    func checkAnalyticsReportRequestStatus(requestId: String) async throws -> (isActive: Bool, stoppedDueToInactivity: Bool) {
        print("📊 [Analytics] 리포트 요청 상태 확인: \(requestId)")

        let urlString = "\(baseURL)/analyticsReportRequests/\(requestId)"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnalyticsReportRequestResponse.self, from: data)

        let stopped = responseData.data.attributes.stoppedDueToInactivity ?? false
        print("✅ [Analytics] 상태: \(stopped ? "비활성" : "활성")")

        return (isActive: !stopped, stoppedDueToInactivity: stopped)
    }

    /// 3. 완성된 리포트 목록 가져오기
    func fetchAnalyticsReports(requestId: String) async throws -> [AnalyticsReportData] {
        print("📊 [Analytics] 리포트 목록 조회: \(requestId)")

        let urlString = "\(baseURL)/analyticsReportRequests/\(requestId)/reports"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnalyticsReportsResponse.self, from: data)

        print("✅ [Analytics] \(responseData.data.count)개 리포트 발견")
        return responseData.data
    }

    /// 4. 리포트 인스턴스 정보 가져오기
    func fetchAnalyticsReportInstances(reportId: String) async throws -> [AnalyticsReportInstanceData] {
        print("📊 [Analytics] 리포트 인스턴스 조회: \(reportId)")

        let urlString = "\(baseURL)/analyticsReports/\(reportId)/instances"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnalyticsReportInstancesResponse.self, from: data)

        print("✅ [Analytics] \(responseData.data.count)개 인스턴스 발견")
        return responseData.data
    }

    /// 5. 세그먼트 데이터 가져오기
    func fetchAnalyticsReportSegments(instanceId: String) async throws -> [AnalyticsReportSegmentData] {
        print("📊 [Analytics] 세그먼트 조회: \(instanceId)")

        let urlString = "\(baseURL)/analyticsReportInstances/\(instanceId)/segments"
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnalyticsReportSegmentsResponse.self, from: data)

        print("✅ [Analytics] \(responseData.data.count)개 세그먼트 발견")
        return responseData.data
    }

    /// 6. CSV 다운로드 및 파싱 (세그먼트 URL에서)
    func downloadAnalyticsSegment(segmentURL: String) async throws -> AnalyticsData {
        print("📊 [Analytics] 세그먼트 다운로드: \(segmentURL)")

        guard let url = URL(string: segmentURL) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        // CSV 파싱
        return try parseAnalyticsCSV(data)
    }

    /// CSV 파싱
    private func parseAnalyticsCSV(_ data: Data) throws -> AnalyticsData {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw ServiceError.csvParsingError
        }

        var analytics = AnalyticsData()

        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return analytics
        }

        // 헤더 파싱
        let header = lines[0].components(separatedBy: ",")

        // 컬럼 인덱스 찾기
        let impressionsIndex = header.firstIndex(of: "Impressions")
        let pageViewsIndex = header.firstIndex(of: "Page Views")
        let sessionsIndex = header.firstIndex(of: "Sessions")
        let activeDevicesIndex = header.firstIndex(of: "Active Devices")
        let crashesIndex = header.firstIndex(of: "Crashes")
        let installsIndex = header.firstIndex(of: "Installs")
        let unitsIndex = header.firstIndex(of: "Units")

        // 데이터 행 파싱 및 합산
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let columns = line.components(separatedBy: ",")

            if let index = impressionsIndex, columns.count > index {
                analytics.impressions += Int(columns[index]) ?? 0
            }
            if let index = pageViewsIndex, columns.count > index {
                analytics.pageViews += Int(columns[index]) ?? 0
            }
            if let index = sessionsIndex, columns.count > index {
                analytics.sessions += Int(columns[index]) ?? 0
            }
            if let index = activeDevicesIndex, columns.count > index {
                analytics.activeDevices += Int(columns[index]) ?? 0
            }
            if let index = crashesIndex, columns.count > index {
                analytics.crashes += Int(columns[index]) ?? 0
            }
            if let index = installsIndex, columns.count > index {
                analytics.installs += Int(columns[index]) ?? 0
            }
            if let index = unitsIndex, columns.count > index {
                analytics.units += Int(columns[index]) ?? 0
            }
        }

        // 전환율 계산 (페이지 조회 → 설치)
        if analytics.pageViews > 0 {
            analytics.conversionRate = Double(analytics.installs) / Double(analytics.pageViews)
        }

        analytics.lastUpdated = Date()

        return analytics
    }

    /// 전체 Analytics 데이터 가져오기 (통합 메서드)
    func fetchAnalyticsData(appID: String, requestId: String) async throws -> AnalyticsData {
        print("📊 [Analytics] 통합 데이터 조회 시작")

        // 1. 리포트 목록 가져오기
        let reports = try await fetchAnalyticsReports(requestId: requestId)

        guard let firstReport = reports.first else {
            print("⚠️ [Analytics] 사용 가능한 리포트 없음")
            return AnalyticsData()
        }

        // 2. 인스턴스 가져오기 (최신 daily 데이터 선호)
        let instances = try await fetchAnalyticsReportInstances(reportId: firstReport.id)

        guard let latestInstance = instances.first(where: { $0.attributes.granularity == "DAILY" }) ?? instances.first else {
            print("⚠️ [Analytics] 사용 가능한 인스턴스 없음")
            return AnalyticsData()
        }

        // 3. 세그먼트 가져오기
        let segments = try await fetchAnalyticsReportSegments(instanceId: latestInstance.id)

        guard let firstSegment = segments.first,
              let segmentURL = firstSegment.attributes.url else {
            print("⚠️ [Analytics] 사용 가능한 세그먼트 없음")
            return AnalyticsData()
        }

        // 4. CSV 다운로드 및 파싱
        let analytics = try await downloadAnalyticsSegment(segmentURL: segmentURL)

        print("✅ [Analytics] 통합 데이터 조회 완료")
        return analytics
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
    case reportNotReady
    case csvParsingError
    
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
        case .reportNotReady:
            return "리포트가 아직 준비되지 않았습니다. 잠시 후 다시 시도해주세요."
        case .csvParsingError:
            return "CSV 데이터를 파싱하는 중 오류가 발생했습니다."
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
