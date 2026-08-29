//
//  CacheManager.swift
//  ReviewManager
//
//  API에서 받은 데이터를 로컬에 영구 보관하는 저장소
//

import Foundation

// MARK: - Local Data Store
/// 한 번 불러온 데이터를 로컬 디스크에 영구 보관하는 저장소.
///
/// 설계 원칙
/// - **데이터를 버리지 않는다**: 만료 시간은 "언제 다시 불러올지"를 정하는 기준일 뿐이다.
///   오래된 데이터라도 지우거나 nil을 돌려주지 않으므로, 오프라인이거나 API가 실패해도
///   마지막으로 받은 내용을 계속 보여줄 수 있다.
/// - **지워지지 않는 위치**: 시스템이 임의로 비울 수 있는 Caches 대신 Application Support에 저장한다.
///   (기존 Caches 데이터는 최초 실행 시 자동 이전한다.)
/// - **덮어쓰지 않고 병합한다**: 새로 받은 데이터에 없는 값(판매·다운로드·분석·아이콘 등)은 기존 값을 유지한다.
@MainActor
class CacheManager {
    static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let storeDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let appsFile = "apps.json"
    private static func reviewsFile(_ appID: String) -> String { "reviews_\(appID).json" }

    /// 오래된 파일 정리 기준. 새로고침 주기와 별개로, 이 기간이 지난 파일만 정리 대상이 된다.
    nonisolated static let defaultRetentionDays = 90

    /// 자동 새로고침 주기(초). 이 시간이 지나면 "오래된 데이터"로 보고 새로 불러오지만,
    /// 기존 데이터는 그대로 남는다.
    var refreshInterval: TimeInterval {
        let hours = UserDefaults.standard.integer(forKey: "cacheExpirationHours")
        // 설정 화면의 "30분" 옵션은 tag 0 이다
        return hours > 0 ? TimeInterval(hours) * 3600 : 30 * 60
    }

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeDirectory = appSupport
            .appendingPathComponent("ReviewManager", isDirectory: true)
            .appendingPathComponent("DataStore", isDirectory: true)

        try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        migrateLegacyCacheIfNeeded()

        print("📦 [CacheManager] 초기화 완료")
        print("   저장 위치: \(storeDirectory.path)")
        print("   새로고침 주기: \(refreshInterval / 60)분")
    }

    /// 예전 버전이 Caches에 저장해 둔 데이터를 Application Support로 옮긴다 (1회성).
    private func migrateLegacyCacheIfNeeded() {
        let legacyDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReviewManagerCache", isDirectory: true)

        guard fileManager.fileExists(atPath: legacyDirectory.path),
              let files = try? fileManager.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        var moved = 0
        for url in files where url.pathExtension == "json" {
            let destination = storeDirectory.appendingPathComponent(url.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                try fileManager.copyItem(at: url, to: destination)
                moved += 1
            } catch {
                print("⚠️ [CacheManager] 이전 실패: \(url.lastPathComponent) - \(error)")
            }
        }

        try? fileManager.removeItem(at: legacyDirectory)
        if moved > 0 {
            print("🚚 [CacheManager] 기존 캐시 \(moved)개를 Application Support로 이전")
        }
    }

    // MARK: - Apps

    /// 앱 목록을 저장한다. 저장된 값 중 새 목록에 없는 정보(판매·분석·아이콘 등)는 그대로 유지된다.
    func cacheApps(_ apps: [AppInfo]) {
        let merged = mergeWithStoredApps(apps)
        save(CachedData(data: merged, timestamp: Date()), filename: Self.appsFile)
        print("✅ [CacheManager] 앱 목록 저장: \(merged.count)개")
    }

    /// 저장된 앱 목록. 오래됐더라도 항상 반환한다 (데이터를 잃지 않기 위해).
    func getCachedApps() -> [AppInfo]? {
        guard let cached: CachedData<[AppInfo]> = load(filename: Self.appsFile) else {
            print("ℹ️ [CacheManager] 저장된 앱 목록 없음")
            return nil
        }
        print("✅ [CacheManager] 저장된 앱 목록 반환: \(cached.data.count)개 (\(Self.ageDescription(cached.timestamp)))")
        return cached.data
    }

    /// 앱 목록을 마지막으로 API에서 받아온 시각.
    var appsCacheDate: Date? {
        (load(filename: Self.appsFile) as CachedData<[AppInfo]>?)?.timestamp
    }

    /// 앱 목록이 새로고침 주기 안에 있는지 여부.
    var isAppsCacheFresh: Bool {
        isFresh(appsCacheDate)
    }

    /// 새로 받은 앱 목록에 로컬에 쌓아둔 데이터를 채워 넣는다.
    /// API 응답에는 판매·다운로드·분석 데이터가 없으므로, 새로고침 때마다 사라지는 것을 막는다.
    func mergeWithStoredApps(_ incoming: [AppInfo]) -> [AppInfo] {
        guard let stored: CachedData<[AppInfo]> = load(filename: Self.appsFile) else { return incoming }

        let storedByID = Dictionary(stored.data.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return incoming.map { app in
            guard let old = storedByID[app.id] else { return app }

            var merged = app
            merged.iconURL = app.iconURL ?? old.iconURL
            merged.currentVersion = app.currentVersion ?? old.currentVersion
            merged.versionState = app.versionState ?? old.versionState
            merged.lastCheckedDate = app.lastCheckedDate ?? old.lastCheckedDate
            merged.downloads30Days = app.downloads30Days ?? old.downloads30Days
            merged.downloadsLastFetched = app.downloadsLastFetched ?? old.downloadsLastFetched
            merged.analytics = app.analytics ?? old.analytics
            merged.analyticsRequestInfo = app.analyticsRequestInfo ?? old.analyticsRequestInfo
            // SalesData.merge는 값을 합산하므로 여기서 호출하면 중복 집계된다.
            // 판매 데이터 병합은 AppState.fetchSalesData가 "없는 날짜만" 가져와 처리한다.
            merged.salesData = app.salesData ?? old.salesData
            return merged
        }
    }

    // MARK: - Reviews

    /// 리뷰를 저장한다. 기존에 저장된 리뷰와 id 기준으로 합치므로,
    /// API가 최근 리뷰만 돌려줘도 예전 리뷰가 사라지지 않는다.
    func cacheReviews(_ reviews: [CustomerReview], for appID: String) {
        let merged = mergeWithStoredReviews(reviews, for: appID)
        save(CachedData(data: merged, timestamp: Date()), filename: Self.reviewsFile(appID))
        print("✅ [CacheManager] 리뷰 저장: \(appID) - \(merged.count)개 (신규 응답 \(reviews.count)개 반영)")
    }

    /// 저장된 리뷰. 오래됐더라도 항상 반환한다.
    func getCachedReviews(for appID: String) -> [CustomerReview]? {
        guard let cached: CachedData<[CustomerReview]> = load(filename: Self.reviewsFile(appID)) else {
            print("ℹ️ [CacheManager] 저장된 리뷰 없음: \(appID)")
            return nil
        }
        print("✅ [CacheManager] 저장된 리뷰 반환: \(appID) - \(cached.data.count)개 (\(Self.ageDescription(cached.timestamp)))")
        return cached.data
    }

    /// 해당 앱의 리뷰를 마지막으로 API에서 받아온 시각.
    func reviewsCacheDate(for appID: String) -> Date? {
        (load(filename: Self.reviewsFile(appID)) as CachedData<[CustomerReview]>?)?.timestamp
    }

    func isReviewsCacheFresh(for appID: String) -> Bool {
        isFresh(reviewsCacheDate(for: appID))
    }

    /// 새로 받은 리뷰와 저장된 리뷰를 id 기준으로 합친다 (같은 id는 새 것이 이긴다 → 응답 상태 갱신).
    func mergeWithStoredReviews(_ incoming: [CustomerReview], for appID: String) -> [CustomerReview] {
        guard let stored: CachedData<[CustomerReview]> = load(filename: Self.reviewsFile(appID)),
              !stored.data.isEmpty else {
            return incoming.sorted { $0.createdDate > $1.createdDate }
        }

        var byID: [String: CustomerReview] = [:]
        for review in stored.data { byID[review.id] = review }
        for review in incoming { byID[review.id] = review }

        return byID.values.sorted { $0.createdDate > $1.createdDate }
    }

    // MARK: - Freshness

    /// 마지막으로 받아온 시각이 새로고침 주기 안에 있는지 여부. nil이면 항상 오래된 것으로 본다.
    func isFresh(_ timestamp: Date?) -> Bool {
        guard let timestamp else { return false }
        return Date().timeIntervalSince(timestamp) <= refreshInterval
    }

    private static func ageDescription(_ timestamp: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(timestamp) / 60)
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        return "\(minutes / 60)시간 전"
    }

    // MARK: - Generic Save/Load

    private func save<T: Codable>(_ data: T, filename: String) {
        let url = storeDirectory.appendingPathComponent(filename)
        do {
            let encoded = try encoder.encode(data)
            // 저장 도중 앱이 종료돼도 기존 파일이 깨지지 않도록 원자적으로 쓴다
            try encoded.write(to: url, options: .atomic)
        } catch {
            print("❌ [CacheManager] 저장 실패: \(filename) - \(error)")
        }
    }

    private func load<T: Codable>(filename: String) -> T? {
        let url = storeDirectory.appendingPathComponent(filename)
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            // 파일이 없는 경우는 정상적인 상황이므로 에러 로그 출력 안함
            return nil
        }
    }

    // MARK: - Store Management

    func clearAllCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try fileManager.removeItem(at: url)
            }
            print("✅ [CacheManager] 저장된 데이터 전체 삭제 완료")
        } catch {
            print("❌ [CacheManager] 삭제 실패: \(error)")
        }
    }

    /// 오래 사용하지 않은 파일만 정리한다. 새로고침 주기와 무관하게, 기본 90일이 지난 파일이 대상이다.
    func clearOldCache(olderThanDays days: Int = CacheManager.defaultRetentionDays) {
        let retention = TimeInterval(days) * 24 * 3600
        do {
            let contents = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            let now = Date()
            var removed = 0

            for url in contents {
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let modificationDate = attributes[.modificationDate] as? Date else {
                    continue
                }

                if now.timeIntervalSince(modificationDate) > retention {
                    try fileManager.removeItem(at: url)
                    removed += 1
                    print("🗑️ [CacheManager] 오래된 파일 삭제: \(url.lastPathComponent)")
                }
            }

            print("✅ [CacheManager] 오래된 데이터 정리 완료 (\(removed)개 삭제)")
        } catch {
            print("❌ [CacheManager] 정리 실패: \(error)")
        }
    }

    func getCacheInfo() -> (files: Int, size: String, oldestDate: Date?) {
        do {
            let contents = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])

            let totalSize = contents.reduce(0) { size, url in
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return size + fileSize
            }

            let oldestDate = contents.compactMap { url -> Date? in
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.modificationDate] as? Date
            }.min()

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: Int64(totalSize))

            return (files: contents.count, size: sizeString, oldestDate: oldestDate)
        } catch {
            return (files: 0, size: "0 B", oldestDate: nil)
        }
    }
}

// MARK: - Cached Data Model
private struct CachedData<T: Codable>: Codable {
    let data: T
    let timestamp: Date
}
