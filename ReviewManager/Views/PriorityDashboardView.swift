//
//  PriorityDashboardView.swift
//  ReviewManager
//
//  우선순위 대시보드 — 모든 앱을 위험(Risk)·기회(Opportunity) 두 축으로
//  점수화해서 "지금 가장 신경 쓸 앱"을 한눈에 보여줍니다. (AppWatch 이식)
//

import SwiftUI

// MARK: - Priority Dashboard

struct PriorityDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var sortMode: PrioritySortMode = .priority

    private var sortedApps: [ScoredApp] {
        switch sortMode {
        case .priority:
            return appState.scoredApps.sorted { $0.priorityScore > $1.priorityScore }
        case .risk:
            return appState.scoredApps.sorted { $0.riskScore > $1.riskScore }
        case .opportunity:
            return appState.scoredApps.sorted { $0.opportunityScore > $1.opportunityScore }
        case .revenue:
            return appState.scoredApps.sorted { $0.proceeds > $1.proceeds }
        }
    }

    private var topRisk: ScoredApp? {
        appState.scoredApps.max { $0.riskScore < $1.riskScore }
    }
    private var topOpportunity: ScoredApp? {
        appState.scoredApps.max { $0.opportunityScore < $1.opportunityScore }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if appState.scoredApps.isEmpty {
                    emptyState
                } else {
                    PriorityHeadlineBanner(headline: topRisk, opportunity: topOpportunity)
                    PriorityLegendRow()

                    LazyVStack(spacing: 12) {
                        ForEach(Array(sortedApps.enumerated()), id: \.element.id) { index, app in
                            PriorityAppCard(rank: index + 1, app: app, sortMode: sortMode)
                                .onTapGesture { open(app) }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if appState.scoredApps.isEmpty {
                appState.computeScoresFromCache()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("우선순위 대시보드")
                        .font(.title2.bold())
                    Text("어떤 앱에 신경 써야 하는지 한눈에")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("정렬", selection: $sortMode) {
                    ForEach(PrioritySortMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .disabled(appState.scoredApps.isEmpty)

                Button {
                    Task { await appState.analyzeAllApps() }
                } label: {
                    Label(appState.isAnalyzing ? "분석 중..." : "분석 새로고침",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isAnalyzing)
            }

            if appState.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(appState.analyzeProgress ?? "분석 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !appState.isDemoMode && !appState.analysisHistory.isEmpty {
                // 분석 기록 드롭다운 — 날짜를 누르면 그 시점 결과를 다시 표시
                Menu {
                    Section("분석 기록") {
                        ForEach(appState.analysisHistory) { snap in
                            Button {
                                appState.showSnapshot(snap)
                            } label: {
                                if snap.date == appState.lastAnalyzedDate {
                                    Label("\(formatDate(snap.date)) · \(snap.apps.count)개 앱", systemImage: "checkmark")
                                } else {
                                    Text("\(formatDate(snap.date)) · \(snap.apps.count)개 앱")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath").font(.caption2)
                        Text("마지막 분석: \(formatDate(appState.lastAnalyzedDate ?? appState.analysisHistory[0].date))")
                            .font(.caption2)
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else if let last = appState.lastAnalyzedDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("마지막 분석: \(formatDate(last))")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            Text("아직 분석할 데이터가 없습니다")
                .font(.headline)

            Text("‘분석 새로고침’을 누르면 모든 앱의 판매·리뷰 데이터를 가져와\n위험·기회 점수를 계산합니다.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if UserDefaults.standard.string(forKey: "vendorNumber")?.isEmpty ?? true {
                Text("⚠️ 매출·다운로드 점수까지 보려면 설정에서 Vendor Number를 입력하세요\n(없어도 리뷰 기반 점수는 계산됩니다)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await appState.analyzeAllApps() }
            } label: {
                Label("지금 분석하기", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isAnalyzing)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func open(_ scored: ScoredApp) {
        guard let app = appState.apps.first(where: { $0.id == scored.id }) else { return }
        Task { await appState.fetchReviews(for: app) }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - Headline Banner

struct PriorityHeadlineBanner: View {
    let headline: ScoredApp?
    let opportunity: ScoredApp?

    var body: some View {
        HStack(spacing: 14) {
            bannerCard(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "지금 가장 신경 쓸 앱",
                name: headline?.name,
                detail: headline.map { "위험 \(Int($0.riskScore)) · 우선순위 \(Int($0.priorityScore))" }
            )
            if let opp = opportunity, opp.id != headline?.id, opp.opportunityScore >= 45 {
                bannerCard(
                    icon: "arrow.up.right.circle.fill",
                    tint: .green,
                    title: "키우면 더 잘 될 앱",
                    name: opp.name,
                    detail: "기회 \(Int(opp.opportunityScore))"
                )
            }
        }
    }

    private func bannerCard(icon: String, tint: Color, title: String, name: String?, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(name ?? "—").font(.title3.bold())
                if let d = detail { Text(d).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)))
    }
}

// MARK: - Legend

struct PriorityLegendRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("위험 = 매출 핵심인데 흔들림 · 기회 = 잘 나가는데 더 키울 여지")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            badge("60+", .red, "즉시")
            badge("35–59", .orange, "주시")
            badge("<35", .green, "안정")
        }
    }
    private func badge(_ t: String, _ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.caption2.bold()).foregroundStyle(c)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - App Card

struct PriorityAppCard: View {
    let rank: Int
    let app: ScoredApp
    let sortMode: PrioritySortMode

    private var primaryScore: Double {
        switch sortMode {
        case .risk: return app.riskScore
        case .opportunity: return app.opportunityScore
        case .revenue, .priority: return app.priorityScore
        }
    }
    private var scoreColor: Color {
        primaryScore >= 60 ? .red : (primaryScore >= 35 ? .orange : .green)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.tertiary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    if let iconURL = app.iconURL, let url = URL(string: iconURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: "app.fill").foregroundColor(.accentColor)
                        }
                        .frame(width: 26, height: 26)
                        .cornerRadius(6)
                    }
                    Text(app.name).font(.headline)
                    Spacer()
                    Text("\(Int(primaryScore))")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(scoreColor)
                }

                // 위험 + 기회 미니바를 항상 동시 표시
                VStack(spacing: 5) {
                    miniBar(label: "위험", value: app.riskScore, color: .orange)
                    miniBar(label: "기회", value: app.opportunityScore, color: .green)
                }

                if !app.flags.isEmpty {
                    PriorityFlowFlags(flags: app.flags)
                }

                HStack(spacing: 22) {
                    metric("매출(추정)", proceedsText)
                    metric("다운로드", "\(app.units)")
                    metric("추세", trendText, color: app.trendPct >= 0 ? .green : .red)
                    metric("평점", ratingText)
                    metric("리뷰", "\(app.reviewCount)")
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
    }

    private var proceedsText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = app.proceeds >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: app.proceeds)) ?? "$0"
    }
    private var trendText: String {
        (app.trendPct >= 0 ? "▲ " : "▼ ") + "\(abs(Int(app.trendPct)))%"
    }
    private var ratingText: String {
        guard let r = app.recentRating else { return "—" }
        var s = String(format: "%.2f★", r)
        if let d = app.ratingDelta { s += String(format: " (%+.2f)", d) }
        return s
    }

    private func miniBar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(value, 100) / 100))
                }
            }
            .frame(height: 7)
            Text("\(Int(value))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
    }
}

// MARK: - Flag chips (wrapping)

struct PriorityFlowFlags: View {
    let flags: [PriorityFlag]
    var body: some View {
        PriorityWrapLayout(spacing: 6) {
            ForEach(flags) { flag in
                Text(flag.text)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(color(for: flag.kind).opacity(0.15), in: Capsule())
                    .foregroundStyle(color(for: flag.kind))
            }
        }
    }
    private func color(for kind: PriorityFlag.Kind) -> Color {
        switch kind {
        case .money: return .yellow
        case .surge, .opportunity: return .green
        case .drop, .lowRating, .ratingDrop: return .red
        }
    }
}

/// 칩/플래그를 여러 줄로 흘려보내는 간단한 Layout.
struct PriorityWrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
