//
//  Scorer.swift
//  ReviewManager
//
//  우선순위 점수화 엔진 (AppWatch의 Scorer를 ReviewManager 모델에 맞게 이식)
//
//  두 개의 축으로 앱을 점수화합니다:
//    • 위험 (Risk)        — 매출 핵심인데 다운로드·평점이 흔들리는 앱. "불을 꺼야 할 앱."
//    • 기회 (Opportunity) — 이미 잘 나가고 상승세라 신경 쓰면 더 커질 앱. "키울 앱."
//
//  priorityScore = max(risk, opportunity) + 0.15 * min(risk, opportunity)
//  → 매출도 크고 급등 중인 앱이 최상단으로, 한쪽 축만 강해도 표면화됩니다.
//

import Foundation

// MARK: - Scored Result

struct ScoredApp: Identifiable, Codable {
    let id: String          // App Store Connect app id
    let name: String
    let iconURL: String?
    let proceeds: Double     // 추정 매출 (Developer Proceeds)
    let units: Int           // 다운로드 수
    let trendPct: Double     // 다운로드 추세 (%)
    let recentRating: Double?
    let ratingDelta: Double?
    let reviewCount: Int

    /// 손봐야 할 압력: 매출 핵심인데 흔들리는 앱.
    let riskScore: Double
    /// 투자할 가치: 이미 잘 나가고 상승 중인 앱.
    let opportunityScore: Double
    /// 통합 우선순위.
    let priorityScore: Double

    let flags: [PriorityFlag]
}

struct PriorityFlag: Identifiable, Hashable, Codable {
    var id = UUID()
    let text: String
    let kind: Kind
    enum Kind: String, Codable { case money, surge, drop, lowRating, ratingDrop, opportunity }
}

/// 한 번의 분석 결과 스냅샷 (날짜 + 점수 목록). 디스크에 저장되어 재실행 후에도 유지된다.
struct AnalysisSnapshot: Identifiable, Codable {
    let id: String
    let date: Date
    let apps: [ScoredApp]
}

// MARK: - Sort Mode

enum PrioritySortMode: String, CaseIterable, Identifiable {
    case priority = "우선순위"
    case risk = "위험 (불 끄기)"
    case opportunity = "기회 (키우기)"
    case revenue = "매출"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .priority: return "flag.fill"
        case .risk: return "exclamationmark.triangle.fill"
        case .opportunity: return "arrow.up.right.circle.fill"
        case .revenue: return "dollarsign.circle.fill"
        }
    }
}

// MARK: - Scorer

enum Scorer {

    // 위험 축 내부 가중치 (합 1.0)
    struct RiskWeights {
        var revenue = 0.40
        var dropTrend = 0.30
        var reviews = 0.20
        var stability = 0.10
    }

    // 기회 축 내부 가중치 (합 1.0)
    struct OppWeights {
        var revenue = 0.45      // 이미 벌고 있음 = 투자할 가치
        var surgeTrend = 0.40   // 빠르게 상승 중
        var goodRating = 0.15   // 건강한 평점 = 증폭할 모멘텀
    }

    /// sales / reviews 는 모두 app.id 를 키로 사용합니다.
    static func score(apps: [AppInfo],
                      sales: [String: SalesData],
                      reviews: [String: [CustomerReview]],
                      riskW: RiskWeights = .init(),
                      oppW: OppWeights = .init()) -> [ScoredApp] {

        let realMaxProceeds = apps.map { sales[$0.id]?.totalRevenue ?? 0 }.max() ?? 0
        let maxProceeds = max(realMaxProceeds, 1)

        // 포트폴리오 차원의 신호 가용성 — 데이터가 전혀 없는 신호는 점수 정규화에서 제외한다.
        // (예: Vendor Number 미설정 → 매출·추세 신호가 모두 0이라 제외해야 리뷰 신호가 0~100 전 범위를 쓴다)
        let portfolioHasRevenue = realMaxProceeds > 0

        var rows: [ScoredApp] = []
        for app in apps {
            let s = sales[app.id]
            let revs = (reviews[app.id] ?? []).sorted { $0.createdDate > $1.createdDate }

            let proceeds = s?.totalRevenue ?? 0
            let units = s?.totalUnits ?? 0

            let revenueSignal = norm(proceeds, 0, maxProceeds)          // 0–100
            let trend = trendPct(s?.dailyData ?? [])                    // % 변화
            let dropSignal = norm(max(0, -trend), 0, 100)               // 하락만
            let surgeSignal = norm(max(0, trend), 0, 100)               // 상승만

            let recent = recentAvgRating(revs)
            let older = olderAvgRating(revs)
            let ratingDelta = (recent != nil && older != nil) ? recent! - older! : nil

            // 위험용 리뷰 압력: 낮은 평점 또는 평점 하락.
            var reviewRisk = 0.0
            if let r = recent {
                let lowPressure = norm(5 - r, 0, 4)                     // 5★→0, 1★→100
                var dropPressure = 0.0
                if let d = ratingDelta, d < 0 { dropPressure = norm(-d, 0, 2) }
                reviewRisk = max(lowPressure, dropPressure)
            }
            // 기회용 평점 건강도: 높고 떨어지지 않음.
            var ratingHealth = 0.0
            if let r = recent {
                ratingHealth = norm(r - 3.0, 0, 2)                      // 3★→0, 5★→100
                if let d = ratingDelta, d < 0 { ratingHealth *= 0.5 }   // 하락 중이면 할인
            }

            // 이 앱에 실제로 존재하는 신호만 사용한다.
            let hasTrend = (s?.dailyData.count ?? 0) >= 4     // 일별 다운로드 추세 계산 가능 여부
            let hasReviews = recent != nil                    // 평점 신호 존재 여부

            // 안정성(stability)은 데이터 소스가 아직 없으므로 항상 제외.
            // 사용 가능한 신호들의 가중치만으로 0~100 범위를 정규화한다.
            let risk = weighted([
                (riskW.revenue,   revenueSignal, portfolioHasRevenue),
                (riskW.dropTrend, dropSignal,    hasTrend),
                (riskW.reviews,   reviewRisk,    hasReviews)
            ])

            let opportunity = weighted([
                (oppW.revenue,    revenueSignal, portfolioHasRevenue),
                (oppW.surgeTrend, surgeSignal,   hasTrend),
                (oppW.goodRating, ratingHealth,  hasReviews)
            ])

            let priority = max(risk, opportunity) + 0.15 * min(risk, opportunity)

            rows.append(ScoredApp(
                id: app.id,
                name: app.name,
                iconURL: app.iconURL,
                proceeds: (proceeds * 100).rounded() / 100,
                units: units,
                trendPct: (trend * 10).rounded() / 10,
                recentRating: recent.map { ($0 * 100).rounded() / 100 },
                ratingDelta: ratingDelta.map { ($0 * 100).rounded() / 100 },
                reviewCount: revs.count,
                riskScore: (risk * 10).rounded() / 10,
                opportunityScore: (opportunity * 10).rounded() / 10,
                priorityScore: (priority * 10).rounded() / 10,
                flags: makeFlags(proceeds: proceeds, maxProceeds: maxProceeds,
                                 trend: trend, recent: recent, ratingDelta: ratingDelta,
                                 opportunity: opportunity)
            ))
        }
        return rows.sorted { $0.priorityScore > $1.priorityScore }
    }

    // MARK: - helpers

    /// 사용 가능한(enabled) 신호의 가중치만으로 0~100 점수를 정규화한다.
    /// 데이터가 없는 신호를 0으로 합산하지 않고 분모에서 제외하므로,
    /// 일부 신호만 있어도 점수가 0~100 전 범위에 고르게 분포한다.
    static func weighted(_ pairs: [(weight: Double, value: Double, enabled: Bool)]) -> Double {
        let denom = pairs.reduce(0.0) { $0 + ($1.enabled ? $1.weight : 0) }
        guard denom > 0 else { return 0 }
        let num = pairs.reduce(0.0) { $0 + ($1.enabled ? $1.weight * $1.value : 0) }
        return num / denom
    }

    /// 일별 다운로드를 전반/후반으로 나눠 증감률(%)을 계산.
    static func trendPct(_ daily: [DailySalesData]) -> Double {
        guard daily.count >= 4 else { return 0 }
        let sorted = daily.sorted { $0.date < $1.date }
        let mid = sorted.count / 2
        let first = sorted[..<mid].reduce(0) { $0 + $1.units }
        let second = sorted[mid...].reduce(0) { $0 + $1.units }
        if first == 0 { return second > 0 ? 100 : 0 }
        return Double(second - first) / Double(first) * 100
    }

    /// 최신 n개 리뷰의 평균 평점 (revs는 최신순 정렬 가정).
    static func recentAvgRating(_ revs: [CustomerReview], n: Int = 20) -> Double? {
        let r = revs.prefix(n).map { Double($0.rating) }.filter { $0 > 0 }
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }

    /// 그 이전 n개 리뷰의 평균 평점.
    static func olderAvgRating(_ revs: [CustomerReview], n: Int = 20) -> Double? {
        let slice = Array(revs.dropFirst(n).prefix(n)).map { Double($0.rating) }.filter { $0 > 0 }
        return slice.isEmpty ? nil : slice.reduce(0, +) / Double(slice.count)
    }

    static func norm(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard hi != lo else { return 0 }
        return min(100, max(0, (v - lo) / (hi - lo) * 100))
    }

    static func makeFlags(proceeds: Double, maxProceeds: Double,
                          trend: Double, recent: Double?, ratingDelta: Double?,
                          opportunity: Double) -> [PriorityFlag] {
        var flags: [PriorityFlag] = []
        if maxProceeds > 0 && proceeds >= 0.25 * maxProceeds {
            flags.append(PriorityFlag(text: "💰 매출 핵심", kind: .money))
        }
        if trend >= 40 {
            flags.append(PriorityFlag(text: "📈 급등 +\(Int(trend))%", kind: .surge))
        } else if trend <= -25 {
            flags.append(PriorityFlag(text: "📉 급락 \(Int(trend))%", kind: .drop))
        }
        if let r = recent, r < 3.5 {
            flags.append(PriorityFlag(text: "⚠️ 평점 \(String(format: "%.1f", r))★", kind: .lowRating))
        }
        if let d = ratingDelta, d <= -0.5 {
            flags.append(PriorityFlag(text: "⭐ 평점 하락 \(String(format: "%+.1f", d))", kind: .ratingDrop))
        }
        if opportunity >= 55 && trend > 0 {
            flags.append(PriorityFlag(text: "🚀 키울 기회", kind: .opportunity))
        }
        return flags
    }
}
