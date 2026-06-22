//
//  DemoData.swift
//  ReviewManager
//
//  데모 모드용 샘플 데이터. App Store Connect 인증 없이 앱의 모든 기능
//  (앱 목록·리뷰·응답·통계·판매·우선순위 대시보드)을 체험할 수 있도록 제공합니다.
//  앱 심사(Guideline 2.1) 시 리뷰어가 전체 기능을 확인하는 용도로도 사용됩니다.
//

import Foundation

enum DemoData {

    /// 데모 모드 전체 데이터 묶음.
    struct Bundle {
        let apps: [AppInfo]
        let reviews: [String: [CustomerReview]]   // appID -> 리뷰 목록
        let sales: [String: SalesData]            // appID -> 판매 데이터
    }

    static func make() -> Bundle {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: today) ?? today }

        // MARK: - 일별 판매 생성 헬퍼 (선형 추세)
        func dailySeries(startUnits: Int, endUnits: Int, pricePerUnit: Double, days: Int = 30) -> [DailySalesData] {
            var out: [DailySalesData] = []
            for i in 0..<days {
                // i=0 이 가장 오래된 날, i=days-1 이 가장 최근
                let t = Double(i) / Double(max(1, days - 1))
                let units = Int(Double(startUnits) + (Double(endUnits - startUnits) * t))
                let jitter = (i % 3 == 0) ? -2 : (i % 5 == 0 ? 3 : 0)
                let u = max(0, units + jitter)
                out.append(DailySalesData(date: day(days - 1 - i), units: u, revenue: Double(u) * pricePerUnit))
            }
            return out
        }

        func salesData(daily: [DailySalesData], countries: [(String, Double)]) -> SalesData {
            var s = SalesData()
            s.dailyData = daily.sorted { $0.date < $1.date }
            s.totalUnits = daily.reduce(0) { $0 + $1.units }
            s.totalRevenue = daily.reduce(0) { $0 + $1.revenue }
            // 국가별 분배 (비율 기반)
            s.countryData = countries.map { code, share in
                CountrySalesData(
                    countryCode: code,
                    units: Int(Double(s.totalUnits) * share),
                    revenue: s.totalRevenue * share
                )
            }.sorted { $0.units > $1.units }
            s.earliestDate = s.dailyData.first?.date
            s.latestDate = s.dailyData.last?.date
            s.lastUpdated = Date()
            return s
        }

        func review(_ id: String, _ rating: Int, _ title: String, _ body: String,
                    _ nick: String, daysAgo: Int, territory: String,
                    responded: Bool = false, responseBody: String = "") -> CustomerReview {
            var response: ReviewResponse? = nil
            if responded {
                response = ReviewResponse(
                    id: "demo-resp-\(id)",
                    responseBody: responseBody,
                    lastModifiedDate: day(max(0, daysAgo - 1)),
                    state: .published
                )
            }
            return CustomerReview(
                id: id,
                rating: rating,
                title: title,
                body: body,
                reviewerNickname: nick,
                createdDate: day(daysAgo),
                territory: territory,
                response: response
            )
        }

        // MARK: - 앱 1: 데일리 가계부 (매출 핵심인데 하락 + 평점 하락 → 위험)
        let app1ID = "demo-app-001"
        let app1Sales = salesData(
            daily: dailySeries(startUnits: 140, endUnits: 48, pricePerUnit: 1.9),
            countries: [("KR", 0.55), ("US", 0.18), ("JP", 0.12), ("DE", 0.08), ("FR", 0.07)]
        )
        let app1Reviews: [CustomerReview] = [
            review("d1-r1", 2, "최근 업데이트 후 느려졌어요", "동기화가 자주 멈춥니다. 예전이 더 좋았어요.", "알뜰살림러", daysAgo: 1, territory: "KR"),
            review("d1-r2", 1, "결제가 두 번 됐어요", "구독 결제 오류가 납니다. 환불 요청합니다.", "money_kim", daysAgo: 2, territory: "KR"),
            review("d1-r3", 2, "위젯이 안 떠요", "잠금화면 위젯이 사라졌습니다.", "J.Park", daysAgo: 4, territory: "KR"),
            review("d1-r4", 3, "그럭저럭", "기능은 많은데 좀 무겁네요.", "saving_us", daysAgo: 6, territory: "US"),
            review("d1-r5", 2, "광고가 너무 많아요", "무료 버전 광고가 과합니다.", "Taro", daysAgo: 8, territory: "JP"),
            review("d1-r6", 5, "예전엔 정말 좋았어요", "오래 잘 썼습니다. 업데이트 전까진 최고였어요.", "budget_master", daysAgo: 30, territory: "KR", responded: true, responseBody: "소중한 의견 감사합니다. 다음 업데이트에서 성능 문제를 개선하겠습니다."),
            review("d1-r7", 5, "가계부 끝판왕", "카테고리 분류가 편리합니다.", "Hana", daysAgo: 33, territory: "KR"),
            review("d1-r8", 4, "Good for tracking", "Solid expense tracker.", "spendwise", daysAgo: 36, territory: "US"),
            review("d1-r9", 5, "추천합니다", "디자인이 깔끔해요.", "minimalist", daysAgo: 39, territory: "DE"),
            review("d1-r10", 4, "만족", "통계 그래프가 보기 좋아요.", "Léa", daysAgo: 41, territory: "FR")
        ]

        // MARK: - 앱 2: 포토 클린업 (상승세 + 높은 평점 → 기회)
        let app2ID = "demo-app-002"
        let app2Sales = salesData(
            daily: dailySeries(startUnits: 22, endUnits: 95, pricePerUnit: 0.0),  // 무료 앱(다운로드 위주)
            countries: [("US", 0.40), ("KR", 0.22), ("GB", 0.15), ("JP", 0.13), ("CN", 0.10)]
        )
        let app2Reviews: [CustomerReview] = [
            review("d2-r1", 5, "사진 정리 신세계", "중복 사진을 한 번에 지웠어요. 저장공간 10GB 확보!", "photo_lover", daysAgo: 1, territory: "KR", responded: true, responseBody: "도움이 되었다니 기쁩니다! 앞으로도 좋은 기능으로 보답하겠습니다 😊"),
            review("d2-r2", 5, "Amazing!", "Cleaned up thousands of duplicates in minutes.", "snapfan", daysAgo: 2, territory: "US"),
            review("d2-r3", 4, "빠르고 정확", "스캔 속도가 정말 빨라요.", "cleaner99", daysAgo: 3, territory: "KR"),
            review("d2-r4", 5, "Best cleaner", "Worth every second.", "tidyphone", daysAgo: 5, territory: "GB"),
            review("d2-r5", 5, "최고의 앱", "친구들에게 추천했어요.", "Yuki", daysAgo: 7, territory: "JP"),
            review("d2-r6", 4, "좋아요", "가끔 큰 라이브러리에서 멈춰요.", "biglib", daysAgo: 10, territory: "US"),
            review("d2-r7", 5, "깔끔", "UI가 직관적입니다.", "design_kim", daysAgo: 14, territory: "KR"),
            review("d2-r8", 5, "강력추천", "무료인데 기능이 알차요.", "freefan", daysAgo: 20, territory: "CN")
        ]

        // MARK: - 앱 3: 워크아웃 타이머 (안정적, 중간)
        let app3ID = "demo-app-003"
        let app3Sales = salesData(
            daily: dailySeries(startUnits: 48, endUnits: 52, pricePerUnit: 0.9),
            countries: [("US", 0.45), ("KR", 0.25), ("GB", 0.18), ("DE", 0.12)]
        )
        let app3Reviews: [CustomerReview] = [
            review("d3-r1", 4, "운동 루틴에 딱", "인터벌 설정이 편해요.", "fit_seoul", daysAgo: 2, territory: "KR"),
            review("d3-r2", 5, "Great timer", "Simple and reliable.", "gymrat", daysAgo: 5, territory: "US"),
            review("d3-r3", 3, "소리가 작아요", "알림음 볼륨 조절이 필요합니다.", "quiet", daysAgo: 9, territory: "GB"),
            review("d3-r4", 4, "좋습니다", "애플워치 연동되면 완벽할 듯.", "watch_want", daysAgo: 15, territory: "KR", responded: true, responseBody: "Apple Watch 연동은 다음 버전에서 준비 중입니다. 기대해 주세요!"),
            review("d3-r5", 5, "Solid", "Does exactly what I need.", "runner", daysAgo: 22, territory: "DE")
        ]

        // MARK: - 앱 4: 메모 위젯 (소규모, 평점 낮음 주의)
        let app4ID = "demo-app-004"
        let app4Sales = salesData(
            daily: dailySeries(startUnits: 9, endUnits: 7, pricePerUnit: 0.0),
            countries: [("KR", 0.6), ("US", 0.25), ("JP", 0.15)]
        )
        let app4Reviews: [CustomerReview] = [
            review("d4-r1", 3, "위젯은 괜찮아요", "동기화가 가끔 안 돼요.", "memo_user", daysAgo: 3, territory: "KR"),
            review("d4-r2", 2, "iCloud 동기화 문제", "기기 간 메모가 안 맞아요.", "cloudy", daysAgo: 6, territory: "US"),
            review("d4-r3", 4, "심플해서 좋음", "딱 필요한 기능만.", "simple_jp", daysAgo: 12, territory: "JP")
        ]

        // MARK: - AppInfo 구성
        func app(_ id: String, _ name: String, _ bundle: String, _ sku: String,
                 version: String, sales: SalesData, analyticsInstalls: Int,
                 unanswered: Int) -> AppInfo {
            var a = AppInfo(
                id: id, name: name, bundleID: bundle, sku: sku,
                primaryLocale: "ko", newReviewsCount: unanswered,
                currentVersion: version, versionState: .readyForSale,
                downloads30Days: sales.totalUnits, downloadsLastFetched: Date()
            )
            a.salesData = sales
            var analytics = AnalyticsData()
            analytics.installs = analyticsInstalls
            analytics.pageViews = Int(Double(analyticsInstalls) * 3.2)
            analytics.impressions = Int(Double(analyticsInstalls) * 11.5)
            analytics.sessions = Int(Double(analyticsInstalls) * 6.1)
            analytics.activeDevices = Int(Double(analyticsInstalls) * 2.4)
            analytics.crashes = max(0, analyticsInstalls / 400)
            analytics.units = sales.totalUnits
            if analytics.pageViews > 0 {
                analytics.conversionRate = Double(analytics.installs) / Double(analytics.pageViews)
            }
            analytics.lastUpdated = Date()
            a.analytics = analytics
            a.analyticsRequestInfo = AnalyticsReportRequestInfo(
                requestId: "demo-req-\(id)",
                appId: id,
                accessType: "ONGOING",
                createdDate: day(20),
                stoppedDueToInactivity: false,
                lastCheckedDate: Date()
            )
            return a
        }

        let apps = [
            app(app1ID, "데일리 가계부", "com.demo.dailybudget", "DEMO-BUDGET",
                version: "3.2.1", sales: app1Sales, analyticsInstalls: app1Sales.totalUnits,
                unanswered: app1Reviews.filter { $0.response == nil }.count),
            app(app2ID, "포토 클린업", "com.demo.photocleanup", "DEMO-PHOTO",
                version: "2.0.4", sales: app2Sales, analyticsInstalls: app2Sales.totalUnits,
                unanswered: app2Reviews.filter { $0.response == nil }.count),
            app(app3ID, "워크아웃 타이머", "com.demo.workouttimer", "DEMO-TIMER",
                version: "1.4.0", sales: app3Sales, analyticsInstalls: app3Sales.totalUnits,
                unanswered: app3Reviews.filter { $0.response == nil }.count),
            app(app4ID, "메모 위젯", "com.demo.memowidget", "DEMO-MEMO",
                version: "1.1.2", sales: app4Sales, analyticsInstalls: app4Sales.totalUnits,
                unanswered: app4Reviews.filter { $0.response == nil }.count)
        ]

        let reviews = [
            app1ID: app1Reviews,
            app2ID: app2Reviews,
            app3ID: app3Reviews,
            app4ID: app4Reviews
        ]

        let sales = [
            app1ID: app1Sales,
            app2ID: app2Sales,
            app3ID: app3Sales,
            app4ID: app4Sales
        ]

        return Bundle(apps: apps, reviews: reviews, sales: sales)
    }
}
