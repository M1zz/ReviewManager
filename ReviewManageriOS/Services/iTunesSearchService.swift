//
//  iTunesSearchService.swift
//  ReviewManageriOS
//
//  iTunes Search API를 통한 앱 아이콘 조회 (iOS)
//

import Foundation

actor iTunesSearchService {
    static let shared = iTunesSearchService()

    private let baseURL = "https://itunes.apple.com/lookup"

    // 로컬 캐시 디렉토리
    private let cacheDirectory: URL

    // 다운로드 중인 번들 ID 추적 (중복 요청 방지)
    private var downloadingBundleIDs: Set<String> = []

    private init() {
        // Application Support/AppIcons 디렉토리 생성
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("AppIcons", isDirectory: true)

        // 디렉토리가 없으면 생성
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            print("✅ [iTunesSearch] 캐시 디렉토리 생성: \(cacheDirectory.path)")
        } catch {
            print("❌ [iTunesSearch] 캐시 디렉토리 생성 실패: \(error)")
        }
    }

    // Bundle ID를 안전한 파일명으로 변환
    private func cacheFileName(for bundleID: String) -> String {
        return bundleID.replacingOccurrences(of: ".", with: "_") + ".png"
    }

    // 로컬 캐시 파일 경로
    private func localCachePath(for bundleID: String) -> URL {
        return cacheDirectory.appendingPathComponent(cacheFileName(for: bundleID))
    }

    // 로컬 캐시 존재 여부 확인 (static 메서드)
    static private func hasLocalCache(for bundleID: String) -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDirectory = appSupport.appendingPathComponent("AppIcons", isDirectory: true)
        let path = cacheDirectory.appendingPathComponent(bundleID.replacingOccurrences(of: ".", with: "_") + ".png")
        return FileManager.default.fileExists(atPath: path.path)
    }

    // 로컬 캐시 URL 가져오기 (static 메서드로 동기 접근)
    static func getCachedIconURL(for bundleID: String) -> String? {
        guard hasLocalCache(for: bundleID) else {
            return nil
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDirectory = appSupport.appendingPathComponent("AppIcons", isDirectory: true)
        let path = cacheDirectory.appendingPathComponent(bundleID.replacingOccurrences(of: ".", with: "_") + ".png")
        return path.absoluteString
    }

    /// Bundle ID로 앱 아이콘 URL 가져오기 (로컬 캐싱)
    func fetchAppIcon(bundleID: String) async throws -> String? {
        // 1. 로컬 캐시 확인
        if Self.hasLocalCache(for: bundleID) {
            let localPath = localCachePath(for: bundleID)
            return localPath.absoluteString
        }

        // 2. 이미 다운로드 중인지 확인
        if downloadingBundleIDs.contains(bundleID) {
            print("⏳ [iTunesSearch] 이미 다운로드 중: \(bundleID)")
            // 잠시 대기 후 재확인
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
            if Self.hasLocalCache(for: bundleID) {
                return localCachePath(for: bundleID).absoluteString
            }
            return nil
        }

        // 3. 다운로드 시작
        downloadingBundleIDs.insert(bundleID)
        defer {
            downloadingBundleIDs.remove(bundleID)
        }

        print("🔍 [iTunesSearch] 네트워크에서 아이콘 다운로드: \(bundleID)")

        do {
            // 4. iTunes API에서 아이콘 URL 검색
            guard var components = URLComponents(string: baseURL) else {
                return nil
            }

            components.queryItems = [
                URLQueryItem(name: "bundleId", value: bundleID),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "limit", value: "1")
            ]

            guard let url = components.url else {
                return nil
            }

            // 5. iTunes API 호출
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ [iTunesSearch] HTTP 오류: \(bundleID)")
                return nil
            }

            let searchResult = try JSONDecoder().decode(iTunesSearchResult.self, from: data)

            guard let app = searchResult.results.first else {
                print("⚠️ [iTunesSearch] 앱을 찾을 수 없음: \(bundleID)")
                return nil
            }

            // 6. 아이콘 URL 추출
            guard let iconURLString = app.artworkUrl512 ?? app.artworkUrl100 ?? app.artworkUrl60,
                  let iconURL = URL(string: iconURLString) else {
                print("⚠️ [iTunesSearch] 아이콘 URL 없음: \(bundleID)")
                return nil
            }

            // 7. 아이콘 이미지 다운로드
            let (imageData, imageResponse) = try await URLSession.shared.data(from: iconURL)

            guard let httpImageResponse = imageResponse as? HTTPURLResponse,
                  httpImageResponse.statusCode == 200 else {
                print("⚠️ [iTunesSearch] 이미지 다운로드 HTTP 오류: \(bundleID)")
                return nil
            }

            // 8. 이미지 데이터 검증
            guard imageData.count > 0 else {
                print("⚠️ [iTunesSearch] 빈 이미지 데이터: \(bundleID)")
                return nil
            }

            // 9. 로컬에 저장
            let localPath = localCachePath(for: bundleID)
            try imageData.write(to: localPath, options: .atomic)

            print("✅ [iTunesSearch] 아이콘 저장 완료: \(bundleID) (\(imageData.count) bytes)")

            // 10. 로컬 파일 경로 반환
            return localPath.absoluteString

        } catch {
            print("❌ [iTunesSearch] 다운로드 실패: \(bundleID) - \(error.localizedDescription)")
            return nil
        }
    }

    /// 특정 앱의 캐시 삭제
    func clearCache(for bundleID: String) {
        let path = localCachePath(for: bundleID)
        try? FileManager.default.removeItem(at: path)
    }

    /// 모든 캐시 삭제
    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 안전한 파일 URL 반환 (file:// 스킴 사용)
    func safeFileURL(for bundleID: String) -> URL? {
        let path = localCachePath(for: bundleID)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        return path
    }
}

// MARK: - iTunes Search API Models

struct iTunesSearchResult: Codable {
    let resultCount: Int
    let results: [iTunesApp]
}

struct iTunesApp: Codable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl512: String?
}
