//
//  ContentView.swift
//  ReviewManager
//
//  메인 화면
//

import SwiftUI
import AppKit
import Charts

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainView()
            } else {
                OnboardingView()
            }
        }
    }
}

// MARK: - Main View
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFilter: ReviewFilter = .all
    @State private var sortOption: SortOption = .newest
    @State private var searchText = ""
    @State private var selectedReview: CustomerReview?
    @State private var showingResponseSheet = false
    @State private var selectedTab: DetailTab = .reviews

    enum DetailTab: String, CaseIterable {
        case reviews = "리뷰"
        case statistics = "통계"

        var icon: String {
            switch self {
            case .reviews: return "text.bubble"
            case .statistics: return "chart.bar"
            }
        }
    }
    
    var filteredReviews: [CustomerReview] {
        var reviews = appState.reviews.filter { selectedFilter.matches($0) }
        
        if !searchText.isEmpty {
            reviews = reviews.filter { review in
                let searchLower = searchText.lowercased()
                return (review.title?.lowercased().contains(searchLower) ?? false) ||
                       (review.body?.lowercased().contains(searchLower) ?? false) ||
                       (review.reviewerNickname?.lowercased().contains(searchLower) ?? false)
            }
        }
        
        return sortOption.sort(reviews)
    }
    
    var body: some View {
        NavigationSplitView {
            // 사이드바: 앱 목록
            AppListSidebar()
        } detail: {
            VStack(spacing: 0) {
            if appState.isDemoMode {
                DemoModeBanner()
            }
            if appState.selectedApp == nil {
                // 앱 미선택 시: 우선순위 대시보드(홈 화면)
                PriorityDashboardView()
            } else {
            // 메인: 탭으로 구분 (리뷰 / 통계)
            VStack(spacing: 0) {
                // 탭 선택
                if appState.selectedApp != nil {
                    Picker("", selection: $selectedTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.icon)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                }

                // 탭 내용
                if selectedTab == .reviews {
                    // 리뷰 탭
                    VStack(spacing: 0) {
                        // 툴바
                        ReviewToolbar(
                            selectedFilter: $selectedFilter,
                            sortOption: $sortOption,
                            searchText: $searchText
                        )

                        Divider()

                        // 리뷰 목록
                        if appState.selectedApp == nil {
                            EmptyStateView(
                                icon: "app.badge",
                                title: "앱을 선택하세요",
                                description: "왼쪽 사이드바에서 앱을 선택하면\n리뷰를 확인할 수 있습니다."
                            )
                        } else if appState.isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .progressViewStyle(.circular)

                                Text("리뷰를 불러오는 중...")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if let app = appState.selectedApp {
                                    Text(app.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if filteredReviews.isEmpty {
                            EmptyStateView(
                                icon: "text.bubble",
                                title: "리뷰가 없습니다",
                                description: "선택한 필터에 해당하는 리뷰가 없습니다."
                            )
                        } else {
                            ReviewListView(
                                reviews: filteredReviews,
                                selectedReview: $selectedReview,
                                showingResponseSheet: $showingResponseSheet
                            )
                        }
                    }
                } else {
                    // 통계 탭
                    if let app = appState.selectedApp {
                        StatisticsView(app: app)
                    } else {
                        EmptyStateView(
                            icon: "app.badge",
                            title: "앱을 선택하세요",
                            description: "왼쪽 사이드바에서 앱을 선택하면\n통계를 확인할 수 있습니다."
                        )
                    }
                }
            }
            }
            }
        }
        .sheet(isPresented: $showingResponseSheet) {
            if let review = selectedReview {
                ResponseSheet(review: review)
                    .environmentObject(appState)
                    .onAppear {
                        print("📋 [MainView] ResponseSheet 표시됨")
                        print("   선택된 리뷰 ID: \(review.id)")
                        print("   appState 전달: \(appState.isAuthenticated ? "인증됨" : "미인증")")
                    }
            }
        }
        .onChange(of: showingResponseSheet) { newValue in
            print("🔄 [MainView] showingResponseSheet 변경: \(newValue)")
            if newValue {
                if let review = selectedReview {
                    print("   선택된 리뷰: \(review.id)")
                } else {
                    print("   ⚠️ selectedReview가 nil입니다!")
                }
            }
        }
        .alert("오류", isPresented: .constant(appState.errorMessage != nil)) {
            Button("확인") {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}

// MARK: - App List Sidebar
struct AppListSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var isEditMode: Bool = false
    @State private var showHiddenApps: Bool = false

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedApp },
            set: { newValue in
                if let app = newValue {
                    print("📱 [AppListSidebar] 앱 선택됨: \(app.name)")
                    Task {
                        print("🔄 [AppListSidebar] 리뷰 조회 시작...")
                        await appState.fetchReviews(for: app)
                        print("✅ [AppListSidebar] 리뷰 조회 완료")
                    }
                }
            }
        )) {
            // 우선순위 대시보드 (홈) 바로가기
            Section {
                Button {
                    appState.selectedApp = nil
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(appState.selectedApp == nil ? .accentColor : .secondary)
                            .frame(width: 24)
                        Text("우선순위 대시보드")
                            .fontWeight(appState.selectedApp == nil ? .semibold : .regular)
                            .foregroundColor(appState.selectedApp == nil ? .accentColor : .primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                if appState.apps.isEmpty && appState.isLoading {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("앱 목록 불러오는 중...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else if appState.visibleApps.isEmpty && !showHiddenApps {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "app.badge")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("앱이 없습니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }

                ForEach(appState.visibleApps) { app in
                    AppRowView(app: app, isEditMode: isEditMode)
                        .tag(app)
                        .contextMenu {
                            Button {
                                appState.hideApp(app.id)
                            } label: {
                                Label("리스트에서 숨기기", systemImage: "eye.slash")
                            }
                        }
                }
                .onMove(perform: isEditMode ? moveApp : nil)
            } header: {
                HStack {
                    Text("내 앱")
                    Spacer()
                    if isEditMode {
                        Text("드래그로 순서 변경")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 숨긴 앱 섹션
            if !appState.hiddenAppIDs.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showHiddenApps) {
                        ForEach(hiddenApps) { app in
                            AppRowView(app: app, isEditMode: false)
                                .opacity(0.6)
                                .contextMenu {
                                    Button {
                                        appState.unhideApp(app.id)
                                    } label: {
                                        Label("다시 보이기", systemImage: "eye")
                                    }
                                }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.secondary)
                            Text("숨긴 앱")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(appState.hiddenAppIDs.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("리뷰 매니저")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        isEditMode.toggle()
                    }
                } label: {
                    Text(isEditMode ? "완료" : "편집")
                }
            }

            ToolbarItem {
                Menu {
                    Button {
                        Task {
                            await appState.fetchApps(forceRefresh: true)
                        }
                    } label: {
                        Label("앱 목록 동기화", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task {
                            await appState.syncAll()
                        }
                    } label: {
                        Label("전체 데이터 동기화", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Button {
                        appState.clearCache()
                    } label: {
                        Label("캐시 삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("동기화 및 캐시 관리")
                .disabled(isEditMode)
            }
        }
        .task {
            if appState.apps.isEmpty {
                await appState.fetchApps()
            }
        }
    }

    // 숨긴 앱 목록 (출시된 앱 또는 상태 미확인 앱 중에서)
    private var hiddenApps: [AppInfo] {
        appState.apps.filter { app in
            // versionState가 nil이거나 출시 상태인 경우만 포함
            let isNotReleased: Bool
            if let state = app.versionState {
                isNotReleased = state != .readyForSale && state != .preorderReadyForSale
            } else {
                isNotReleased = false
            }
            return !isNotReleased && appState.hiddenAppIDs.contains(app.id)
        }
    }

    private func moveApp(from source: IndexSet, to destination: Int) {
        appState.moveApp(from: source, to: destination)
    }

    // 상태에 따른 색상
    private func stateColor(for state: AppVersionState) -> Color {
        switch state.badgeColor {
        case "green":
            return .green
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "red":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - App Row View
struct AppRowView: View {
    let app: AppInfo
    let isEditMode: Bool

    var body: some View {
        HStack {
            // 드래그 핸들 (편집 모드일 때만 표시)
            if isEditMode {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // 앱 아이콘
            if let iconURL = app.iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "app.fill")
                        .foregroundColor(.accentColor)
                }
                .frame(width: 32, height: 32)
                .cornerRadius(7)
            } else {
                Image(systemName: "app.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 버전 표시
                    if let version = app.currentVersion {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 상태 표시
                if let state = app.versionState {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor(for: state))
                            .frame(width: 6, height: 6)
                        Text(state.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 응답 대기 중인 리뷰 뱃지 (초록색)
            if app.newReviewsCount > 0 {
                Text("\(app.newReviewsCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func stateColor(for state: AppVersionState) -> Color {
        switch state.badgeColor {
        case "green":
            return .green
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "red":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Review Toolbar
struct ReviewToolbar: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedFilter: ReviewFilter
    @Binding var sortOption: SortOption
    @Binding var searchText: String
    
    var body: some View {
        HStack(spacing: 16) {
            // 앱 이름
            if let app = appState.selectedApp {
                HStack(spacing: 8) {
                    // 앱 아이콘
                    if let iconURL = app.iconURL, let url = URL(string: iconURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: "app.fill")
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 24, height: 24)
                        .cornerRadius(5)
                    } else {
                        Image(systemName: "app.fill")
                            .foregroundColor(.accentColor)
                    }

                    Text(app.name)
                        .font(.headline)
                }
            }
            
            Spacer()
            
            // 통계
            if !appState.reviews.isEmpty {
                ReviewStats(reviews: appState.reviews)
            }
            
            Divider()
                .frame(height: 20)
            
            // 필터
            Picker("필터", selection: $selectedFilter) {
                ForEach(ReviewFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            
            // 정렬
            Picker("정렬", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            
            // 검색
            TextField("검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            
            // 마지막 갱신 시각 (로컬에 저장된 데이터 기준)
            if let lastUpdate = appState.lastReviewsUpdate {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                    Text(lastUpdate, style: .relative) + Text(" 전")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .help("마지막으로 App Store Connect에서 리뷰를 받아온 시각입니다. 그 전까지는 로컬에 저장된 데이터를 보여줍니다.")
            }

            // 새로고침
            Button {
                Task {
                    await appState.refreshReviews()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("리뷰 새로고침")
            .disabled(appState.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Review Stats
struct ReviewStats: View {
    let reviews: [CustomerReview]
    
    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }
    
    var respondedCount: Int {
        reviews.filter { $0.response != nil }.count
    }
    
    var body: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "star.fill",
                value: String(format: "%.1f", averageRating),
                color: .yellow
            )
            
            StatBadge(
                icon: "text.bubble.fill",
                value: "\(reviews.count)",
                color: .blue
            )
            
            StatBadge(
                icon: "checkmark.bubble.fill",
                value: "\(respondedCount)/\(reviews.count)",
                color: .green
            )
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Review List View
struct ReviewListView: View {
    let reviews: [CustomerReview]
    @Binding var selectedReview: CustomerReview?
    @Binding var showingResponseSheet: Bool
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(reviews) { review in
                    ReviewCard(
                        review: review,
                        onRespond: {
                            print("👆 [ReviewListView] 응답하기 버튼 클릭")
                            print("   리뷰 ID: \(review.id)")
                            print("   리뷰 제목: \(review.title ?? "제목 없음")")
                            selectedReview = review
                            print("   selectedReview 설정 완료")
                            showingResponseSheet = true
                            print("   showingResponseSheet = true 설정 완료")
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Review Card
struct ReviewCard: View {
    @EnvironmentObject var appState: AppState
    let review: CustomerReview
    let onRespond: () -> Void
    
    @State private var isExpanded = false
    
    var ratingColor: Color {
        switch review.rating {
        case 5: return .green
        case 4: return .blue
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack {
                // 별점
                Text(review.starsDisplay)
                    .foregroundColor(ratingColor)

                Spacer()

                // 지역
                Text(review.territory)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                // 새로운 리뷰 뱃지 (빨간색)
                if review.isNew {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                        Text("New")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(10)
                }
                // 응답 대기 뱃지 (초록색)
                else if review.isWaitingForResponse {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 6))
                        Text("응답대기")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .cornerRadius(10)
                }

                // 날짜
                Text(review.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 제목
            if let title = review.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
            }
            
            // 본문
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .lineLimit(isExpanded ? nil : 3)
                    .onTapGesture {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }
            }

            // 번역 (Apple 온디바이스 번역)
            ReviewTranslationView(reviewTitle: review.title, reviewBody: review.body)
            
            // 작성자
            if let nickname = review.reviewerNickname {
                Text("— \(nickname)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 응답
            if let response = review.response {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .foregroundColor(.accentColor)
                        Text("개발자 응답")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text(response.state.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(response.state == .published ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .cornerRadius(4)
                        
                        Text(response.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(response.responseBody)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    HStack {
                        Spacer()
                        ReviewCopyButton(text: response.responseBody, titleKey: "review.copy.response")
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.05))
                .cornerRadius(8)
            }
            
            // 액션 버튼
            HStack {
                ReviewCopyButton(text: ReviewClipboard.joined(title: review.title, body: review.body))

                Spacer()
                
                if review.response != nil {
                    Button {
                        Task {
                            await appState.deleteResponse(for: review)
                        }
                    } label: {
                        Label("응답 삭제", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    
                    Button {
                        onRespond()
                    } label: {
                        Label("응답 수정", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        onRespond()
                    } label: {
                        Label("응답하기", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Response Sheet
struct ResponseSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let review: CustomerReview
    @State private var responseText: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text(review.response != nil ? "리뷰 응답 수정" : "리뷰 응답 작성")
                    .font(.headline)
                Spacer()
                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSending)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 에러 메시지
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.callout)
                                .foregroundColor(.red)
                            Spacer()
                            Button("닫기") {
                                errorMessage = nil
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // 원본 리뷰
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("원본 리뷰")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    copyReviewToPasteboard()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("복사")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }

                            Divider()

                            HStack {
                                Text(review.starsDisplay)
                                Spacer()
                                Text(review.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let title = review.title {
                                Text(title)
                                    .font(.headline)
                            }

                            if let body = review.body {
                                Text(body)
                                    .font(.body)
                            }

                            if let nickname = review.reviewerNickname {
                                Text("— \(nickname)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // 번역 (Apple 온디바이스 번역)
                            ReviewTranslationView(reviewTitle: review.title, reviewBody: review.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    // 응답 입력
                    GroupBox("응답 작성") {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                if responseText.isEmpty {
                                    Text("여기에 응답을 작성하세요...")
                                        .foregroundColor(Color.secondary.opacity(0.5))
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }

                                TextEditor(text: $responseText)
                                    .font(.body)
                                    .frame(minHeight: 150)
                                    .focused($isTextEditorFocused)
                                    .disabled(isSending)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isTextEditorFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isTextEditorFocused ? 2 : 1)
                            )

                            HStack {
                                Text("\(responseText.count) / 5970")
                                    .font(.caption)
                                    .foregroundColor(responseText.count > 5970 ? .red : .secondary)

                                Spacer()

                                Button("전송") {
                                    sendResponse()
                                }
                                .keyboardShortcut(.defaultAction)
                                .buttonStyle(.borderedProminent)
                                .disabled(responseText.isEmpty || responseText.count > 5970 || isSending)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 550)
        .overlay {
            if isSending {
                ZStack {
                    // 반투명 배경
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    // 로딩 카드
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(.circular)

                        Text("응답 전송 중...")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("잠시만 기다려주세요")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(color: .black.opacity(0.3), radius: 20)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSending)
        .onAppear {
            print("📝 [ResponseSheet] onAppear 시작")
            print("   리뷰 ID: \(review.id)")
            print("   기존 응답: \(review.response != nil ? "있음" : "없음")")

            if let existingResponse = review.response {
                responseText = existingResponse.responseBody
                print("   기존 응답 텍스트 로드: \(responseText.prefix(50))...")
            }

            // TextEditor에 자동 포커스
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextEditorFocused = true
                print("   TextEditor 포커스 설정 완료")
            }

            print("✅ [ResponseSheet] onAppear 완료")
        }
    }

    private func copyReviewToPasteboard() {
        var content = ""

        // 제목 추가
        if let title = review.title, !title.isEmpty {
            content += title + "\n\n"
        }

        // 본문 추가
        if let body = review.body, !body.isEmpty {
            content += body
        }

        // 클립보드에 복사
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        print("✅ [ResponseSheet] 리뷰 복사 완료")
    }

    private func sendResponse() {
        print("🚀 [ResponseSheet] sendResponse 시작")
        print("   리뷰 ID: \(review.id)")
        print("   응답 텍스트 길이: \(responseText.count)")
        print("   응답 내용: \(responseText.prefix(100))...")

        isSending = true
        errorMessage = nil

        Task {
            print("📤 [ResponseSheet] AppState.respondToReview 호출 시작")
            await appState.respondToReview(review, response: responseText)
            print("✅ [ResponseSheet] AppState.respondToReview 호출 완료")

            await MainActor.run {
                if let error = appState.errorMessage {
                    // 에러 발생 시 메시지 표시
                    print("❌ [ResponseSheet] 에러 발생: \(error)")
                    errorMessage = error
                    appState.errorMessage = nil
                    isSending = false
                } else {
                    // 성공 시 닫기
                    print("✅ [ResponseSheet] 응답 전송 성공, sheet 닫기")
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Demo Mode Banner
struct DemoModeBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("데모 모드")
                    .font(.caption.bold())
                Text("샘플 데이터로 둘러보는 중입니다. 변경 사항은 저장되지 않습니다.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("종료") {
                appState.logout()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - Statistics View
struct StatisticsView: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo

    @State private var selectedPeriod: StatsPeriod = .days30

    enum StatsPeriod: String, CaseIterable {
        case day1 = "1일"
        case days7 = "7일"
        case days30 = "30일"
        case all = "전체"

        var days: Int? {
            switch self {
            case .day1: return 1
            case .days7: return 7
            case .days30: return 30
            case .all: return nil
            }
        }
    }

    var filteredReviews: [CustomerReview] {
        guard let days = selectedPeriod.days else {
            return appState.reviews
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return appState.reviews.filter { review in
            review.createdDate >= cutoffDate
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 기간 선택 필터
                HStack {
                    Text("기간")
                        .font(.headline)

                    Picker("", selection: $selectedPeriod) {
                        ForEach(StatsPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                    Spacer()
                }
                .padding(.horizontal)

                // 다운로드 통계
                DownloadStatsCard(app: app)

                // 판매 분석 데이터 (Sales Reports)
                SalesDataCard(app: app, period: selectedPeriod)

                // Analytics Reports (App Store Engagement)
                AnalyticsReportsCard(app: app)

                // 주요 지표 요약
                KeyMetricsCard(reviews: filteredReviews)

                // 리뷰 통계
                ReviewStatsCard(reviews: filteredReviews)

                // 국가별 분포
                CountryDistributionCard(reviews: filteredReviews)

                // 시간별 트렌드
                ReviewTrendCard(reviews: filteredReviews, period: selectedPeriod)

                // 응답 통계
                ResponseStatsCard(reviews: filteredReviews)

                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Download Statistics Card
struct DownloadStatsCard: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("다운로드 통계", systemImage: "arrow.down.circle.fill")
                    .font(.headline)

                Spacer()

                Button {
                    refreshDownloads()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing || appState.isLoading)
            }

            Divider()

            if let downloads = app.downloads30Days {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("최근 30일")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(app.formattedDownloads ?? "\(downloads)")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.blue)
                        }

                        Spacer()
                    }

                    if let lastFetched = app.downloadsLastFetched {
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("마지막 업데이트: \(formatDate(lastFetched))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("다운로드 통계를 가져오려면 새로고침 버튼을 클릭하세요")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if UserDefaults.standard.string(forKey: "vendorNumber")?.isEmpty ?? true {
                        Text("⚠️ 설정에서 Vendor Number를 먼저 입력해주세요")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            if isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("30일 데이터 수집 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    func refreshDownloads() {
        isRefreshing = true

        Task {
            await appState.fetchDownloadStatistics(for: app)

            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - Sales Data Card
struct SalesDataCard: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo
    let period: StatisticsView.StatsPeriod

    @State private var isRefreshing = false
    @State private var salesData: SalesData?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("판매 및 다운로드 분석", systemImage: "chart.bar.fill")
                    .font(.headline)

                Spacer()

                Button {
                    refreshSalesData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing || appState.isLoading)
            }

            Divider()

            if let salesData = salesData {
                // 주요 지표
                SalesMetricView(
                    title: "총 다운로드",
                    value: salesData.formattedNumber(salesData.totalUnits),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )

                // 국가별 상위 10개 (바 차트)
                if !salesData.countryData.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("상위 국가")
                            .font(.headline)
                            .padding(.top, 8)

                        let topCountries = Array(salesData.countryData.prefix(10))

                        Chart(topCountries, id: \.countryCode) { country in
                            BarMark(
                                x: .value("다운로드", country.units),
                                y: .value("국가", countryName(for: country.countryCode))
                            )
                            .foregroundStyle(Color.blue.gradient)
                            .annotation(position: .trailing) {
                                Text("\(country.units)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(position: .bottom)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel() {
                                    if let country = value.as(String.self) {
                                        Text(country)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .frame(height: CGFloat(topCountries.count * 35))
                    }
                    .padding(.vertical, 8)
                }

                // 일별 트렌드 (바 차트)
                if !salesData.dailyData.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("일별 다운로드 트렌드")
                            .font(.headline)
                            .padding(.top, 8)

                        let recentData = Array(salesData.dailyData.suffix(14))

                        Chart(recentData) { daily in
                            BarMark(
                                x: .value("날짜", daily.date, unit: .day),
                                y: .value("다운로드", daily.units)
                            )
                            .foregroundStyle(Color.blue.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) { value in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                AxisGridLine()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 200)
                    }
                    .padding(.vertical, 8)
                }

                if let lastUpdated = salesData.lastUpdated {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("마지막 업데이트: \(formatDate(lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.top, 8)
                }
            } else if let errorMessage = errorMessage {
                // 에러 표시
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if UserDefaults.standard.string(forKey: "vendorNumber")?.isEmpty ?? true {
                        Text("⚠️ 설정에서 Vendor Number를 먼저 입력해주세요")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Button("다시 시도") {
                        refreshSalesData()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("판매 데이터를 가져오려면 새로고침 버튼을 클릭하세요")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("최근 \(period.days ?? 30)일간의 데이터를 불러옵니다")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if UserDefaults.standard.string(forKey: "vendorNumber")?.isEmpty ?? true {
                        Text("⚠️ 설정에서 Vendor Number를 먼저 입력해주세요")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            if isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("판매 데이터 수집 중... (최대 \(period.days ?? 30)개의 보고서)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            // 캐시된 데이터가 있으면 표시
            if let cachedSalesData = app.salesData {
                salesData = cachedSalesData
            }
        }
    }

    func refreshSalesData() {
        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                let days = period.days ?? 30
                let fetchedSalesData = try await appState.fetchSalesData(for: app, days: days)

                await MainActor.run {
                    salesData = fetchedSalesData
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "판매 데이터를 가져올 수 없습니다: \(error.localizedDescription)"
                    isRefreshing = false
                }
            }
        }
    }

    func countryName(for code: String) -> String {
        let locale = Locale(identifier: "ko_KR")
        return locale.localizedString(forRegionCode: code) ?? code
    }

    func formatDayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd (E)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - Analytics Reports Card
struct AnalyticsReportsCard: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo

    @State private var isCreatingRequest = false
    @State private var isRefreshing = false
    @State private var analytics: AnalyticsData?
    @State private var errorMessage: String?
    @State private var requestStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Analytics Reports (App Store 분석)", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                Spacer()

                if app.analyticsRequestInfo != nil {
                    Button {
                        refreshAnalytics()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing || appState.isLoading)
                }
            }

            Divider()

            if let requestInfo = app.analyticsRequestInfo {
                // 요청이 있는 경우
                if requestInfo.stoppedDueToInactivity == true {
                    // 비활성 상태
                    VStack(spacing: 12) {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text("리포트 생성이 중지되었습니다")
                            .font(.callout)
                            .fontWeight(.semibold)

                        Text("오랫동안 데이터를 가져오지 않아 비활성 상태입니다.\n새 요청을 생성하세요.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("새 요청 생성") {
                            Task {
                                await recreateRequest()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if let analytics = analytics {
                    // 주요 지표 요약 (그리드)
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        AnalyticsSummaryView(
                            title: "노출 수",
                            value: analytics.formattedNumber(analytics.impressions),
                            icon: "eye.fill",
                            color: .blue
                        )

                        AnalyticsSummaryView(
                            title: "페이지 뷰",
                            value: analytics.formattedNumber(analytics.pageViews),
                            icon: "doc.text.fill",
                            color: .green
                        )

                        AnalyticsSummaryView(
                            title: "설치 수",
                            value: analytics.formattedNumber(analytics.installs),
                            icon: "arrow.down.circle.fill",
                            color: .orange
                        )

                        AnalyticsSummaryView(
                            title: "전환율",
                            value: analytics.formattedConversionRate,
                            icon: "percent",
                            color: .pink
                        )
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // 지표별 바 차트
                    AnalyticsMetricsChartView(analytics: analytics)

                    if let lastUpdated = analytics.lastUpdated {
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("마지막 업데이트: \(formatDate(lastUpdated))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("다시 시도") {
                            refreshAnalytics()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // 요청은 있지만 아직 데이터 없음
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("리포트 생성 대기 중")
                            .font(.callout)
                            .fontWeight(.semibold)

                        VStack(spacing: 4) {
                            Text("요청 생성일: \(formatDate(requestInfo.createdDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("첫 리포트는 생성 후 1-2일 소요됩니다")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("이후에는 매일 자동으로 업데이트됩니다")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                        Button("지금 확인해보기") {
                            refreshAnalytics()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                // 요청이 없는 경우
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Analytics Reports 시작하기")
                        .font(.callout)
                        .fontWeight(.semibold)

                    Text("App Store 노출, 페이지 뷰, 세션 등\n마케팅 분석 데이터를 확인하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(isCreatingRequest ? "요청 생성 중..." : "리포트 요청 생성") {
                        Task {
                            await createRequest()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingRequest)
                    .padding(.top, 8)

                    Text("⏳ 첫 리포트는 1-2일 후 확인 가능합니다")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            if isRefreshing || isCreatingRequest {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(isCreatingRequest ? "요청 생성 중..." : "데이터 확인 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !requestStatus.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(requestStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            if let cachedAnalytics = app.analytics {
                analytics = cachedAnalytics
            }
        }
    }

    func createRequest() async {
        isCreatingRequest = true
        errorMessage = nil
        requestStatus = ""

        do {
            let _ = try await appState.ensureAnalyticsReportRequest(for: app)
            await MainActor.run {
                requestStatus = "✅ 요청이 생성되었습니다. 1-2일 후 데이터를 확인하세요."
                isCreatingRequest = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "요청 생성 실패: \(error.localizedDescription)"
                isCreatingRequest = false
            }
        }
    }

    func recreateRequest() async {
        await createRequest()
    }

    func refreshAnalytics() {
        isRefreshing = true
        errorMessage = nil
        requestStatus = ""

        Task {
            do {
                let fetchedAnalytics = try await appState.fetchAnalytics(for: app)

                await MainActor.run {
                    analytics = fetchedAnalytics
                    requestStatus = "✅ 데이터를 성공적으로 가져왔습니다"
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    let errorDesc = error.localizedDescription
                    if errorDesc.contains("리포트가 아직 준비되지 않았습니다") {
                        errorMessage = "리포트가 아직 준비되지 않았습니다.\n요청 생성 후 1-2일 소요됩니다."
                    } else {
                        errorMessage = "데이터를 가져올 수 없습니다: \(errorDesc)"
                    }
                    isRefreshing = false
                }
            }
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - Analytics Summary View
struct AnalyticsSummaryView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)

                Spacer()
            }

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Analytics Metrics Chart View
struct AnalyticsMetricsChartView: View {
    let analytics: AnalyticsData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("지표 비교")
                .font(.headline)

            Chart(metricsData) { metric in
                BarMark(
                    x: .value("값", metric.value),
                    y: .value("지표", metric.name)
                )
                .foregroundStyle(metric.color.gradient)
                .annotation(position: .trailing) {
                    Text(analytics.formattedNumber(Int(metric.value)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .frame(height: CGFloat(metricsData.count * 40))
        }
    }

    private var metricsData: [MetricData] {
        [
            MetricData(name: "노출 수", value: Double(analytics.impressions), color: .blue),
            MetricData(name: "페이지 뷰", value: Double(analytics.pageViews), color: .green),
            MetricData(name: "세션", value: Double(analytics.sessions), color: .purple),
            MetricData(name: "설치", value: Double(analytics.installs), color: .orange),
            MetricData(name: "활성 기기", value: Double(analytics.activeDevices), color: .indigo),
            MetricData(name: "크래시", value: Double(analytics.crashes), color: .red)
        ].filter { $0.value > 0 }
    }

    struct MetricData: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
        let color: Color
    }
}

// MARK: - Sales Metric View
struct SalesMetricView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)

                Spacer()
            }

            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)

            Text(title)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Key Metrics Card
struct KeyMetricsCard: View {
    let reviews: [CustomerReview]

    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        let sum = reviews.reduce(0) { $0 + $1.rating }
        return Double(sum) / Double(reviews.count)
    }

    var positiveReviews: Int {
        reviews.filter { $0.rating >= 4 }.count
    }

    var negativeReviews: Int {
        reviews.filter { $0.rating <= 2 }.count
    }

    var neutralReviews: Int {
        reviews.filter { $0.rating == 3 }.count
    }

    var newReviews: Int {
        reviews.filter { $0.isNew }.count
    }

    var responseRate: Double {
        guard !reviews.isEmpty else { return 0 }
        let respondedCount = reviews.filter { $0.response != nil }.count
        return Double(respondedCount) / Double(reviews.count) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("주요 지표", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("선택한 기간에 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    MetricItem(
                        title: "평균 평점",
                        value: String(format: "%.2f", averageRating),
                        icon: "star.fill",
                        color: .yellow
                    )

                    MetricItem(
                        title: "총 리뷰",
                        value: "\(reviews.count)",
                        icon: "text.bubble.fill",
                        color: .blue
                    )

                    MetricItem(
                        title: "긍정적",
                        value: "\(positiveReviews)",
                        subtitle: String(format: "%.0f%%", Double(positiveReviews) / Double(reviews.count) * 100),
                        icon: "hand.thumbsup.fill",
                        color: .green
                    )

                    MetricItem(
                        title: "부정적",
                        value: "\(negativeReviews)",
                        subtitle: String(format: "%.0f%%", Double(negativeReviews) / Double(reviews.count) * 100),
                        icon: "hand.thumbsdown.fill",
                        color: .red
                    )

                    MetricItem(
                        title: "중립",
                        value: "\(neutralReviews)",
                        subtitle: String(format: "%.0f%%", Double(neutralReviews) / Double(reviews.count) * 100),
                        icon: "minus.circle.fill",
                        color: .orange
                    )

                    MetricItem(
                        title: "응답률",
                        value: String(format: "%.0f%%", responseRate),
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    MetricItem(
                        title: "신규 리뷰",
                        value: "\(newReviews)",
                        icon: "sparkles",
                        color: .purple
                    )

                    MetricItem(
                        title: "미응답",
                        value: "\(reviews.count - reviews.filter { $0.response != nil }.count)",
                        icon: "exclamationmark.circle.fill",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Metric Item
struct MetricItem: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 20, weight: .bold))

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Review Statistics Card
struct ReviewStatsCard: View {
    let reviews: [CustomerReview]

    var ratingDistribution: [Int: Int] {
        var distribution: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for review in reviews {
            distribution[review.rating, default: 0] += 1
        }
        return distribution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("평점 분포", systemImage: "star.bubble.fill")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("선택한 기간에 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { rating in
                        RatingBar(
                            rating: rating,
                            count: ratingDistribution[rating] ?? 0,
                            total: reviews.count
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Country Distribution Card
struct CountryDistributionCard: View {
    let reviews: [CustomerReview]

    var countryDistribution: [(country: String, count: Int)] {
        let grouped = Dictionary(grouping: reviews, by: { $0.territory })
        return grouped.map { (country: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("국가별 리뷰 분포", systemImage: "globe")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("선택한 기간에 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(countryDistribution, id: \.country) { item in
                        HStack {
                            Text(countryName(for: item.country))
                                .font(.subheadline)
                                .frame(width: 100, alignment: .leading)

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 20)
                                        .cornerRadius(4)

                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(
                                            width: geometry.size.width * (Double(item.count) / Double(reviews.count)),
                                            height: 20
                                        )
                                        .cornerRadius(4)

                                    Text("\(item.count)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.leading, 8)
                                }
                            }
                            .frame(height: 20)

                            Text(String(format: "%.1f%%", Double(item.count) / Double(reviews.count) * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    func countryName(for code: String) -> String {
        let locale = Locale(identifier: "ko_KR")
        return locale.localizedString(forRegionCode: code) ?? code
    }
}

// MARK: - Review Trend Card
struct ReviewTrendCard: View {
    let reviews: [CustomerReview]
    let period: StatisticsView.StatsPeriod

    var trendData: [(date: String, count: Int)] {
        let calendar = Calendar.current
        let sortedReviews = reviews.sorted { $0.createdDate < $1.createdDate }

        switch period {
        case .day1:
            // 시간별
            let grouped = Dictionary(grouping: sortedReviews) { review -> String in
                let date = review.createdDate
                let hour = calendar.component(.hour, from: date)
                return "\(hour)시"
            }
            return grouped.map { (date: $0.key, count: $0.value.count) }
                .sorted { $0.date < $1.date }

        case .days7, .days30:
            // 일별
            let grouped = Dictionary(grouping: sortedReviews) { review -> String in
                let date = review.createdDate
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d"
                return formatter.string(from: date)
            }
            return grouped.map { (date: $0.key, count: $0.value.count) }
                .sorted { $0.date < $1.date }

        case .all:
            // 월별
            let grouped = Dictionary(grouping: sortedReviews) { review -> String in
                let date = review.createdDate
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/M"
                return formatter.string(from: date)
            }
            return grouped.map { (date: $0.key, count: $0.value.count) }
                .sorted { $0.date < $1.date }
        }
    }

    var maxCount: Int {
        trendData.map { $0.count }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("리뷰 추이", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("선택한 기간에 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(Array(trendData.enumerated()), id: \.offset) { index, item in
                            VStack(spacing: 4) {
                                Text("\(item.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(
                                        width: 40,
                                        height: max(20, CGFloat(item.count) / CGFloat(maxCount) * 150)
                                    )
                                    .cornerRadius(4)

                                Text(item.date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 40)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Response Stats Card
struct ResponseStatsCard: View {
    let reviews: [CustomerReview]

    var respondedReviews: [CustomerReview] {
        reviews.filter { $0.response != nil }
    }

    var averageResponseTime: TimeInterval? {
        let responseTimes = respondedReviews.compactMap { review -> TimeInterval? in
            guard let responseDate = review.response?.lastModifiedDate else {
                return nil
            }
            return responseDate.timeIntervalSince(review.createdDate)
        }

        guard !responseTimes.isEmpty else { return nil }
        return responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    var fastResponses: Int {
        respondedReviews.filter { review in
            guard let responseDate = review.response?.lastModifiedDate else {
                return false
            }
            let hours = responseDate.timeIntervalSince(review.createdDate) / 3600
            return hours < 24
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("응답 분석", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("선택한 기간에 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    MetricItem(
                        title: "총 응답",
                        value: "\(respondedReviews.count)",
                        icon: "checkmark.bubble.fill",
                        color: .green
                    )

                    MetricItem(
                        title: "응답률",
                        value: String(format: "%.0f%%", Double(respondedReviews.count) / Double(reviews.count) * 100),
                        icon: "percent",
                        color: .blue
                    )

                    MetricItem(
                        title: "24시간 내 응답",
                        value: "\(fastResponses)",
                        subtitle: String(format: "%.0f%%", Double(fastResponses) / Double(max(1, respondedReviews.count)) * 100),
                        icon: "bolt.fill",
                        color: .orange
                    )

                    if let avgTime = averageResponseTime {
                        MetricItem(
                            title: "평균 응답 시간",
                            value: formatTimeInterval(avgTime),
                            icon: "clock.fill",
                            color: .purple
                        )
                    } else {
                        MetricItem(
                            title: "평균 응답 시간",
                            value: "-",
                            icon: "clock.fill",
                            color: .purple
                        )
                    }
                }

                Divider()

                // 응답률을 평점별로 표시
                VStack(alignment: .leading, spacing: 8) {
                    Text("평점별 응답률")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach([5, 4, 3, 2, 1], id: \.self) { rating in
                        let ratingReviews = reviews.filter { $0.rating == rating }
                        let respondedCount = ratingReviews.filter { $0.response != nil }.count
                        let total = ratingReviews.count

                        if total > 0 {
                            ResponseRateBar(
                                rating: rating,
                                responded: respondedCount,
                                total: total
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let days = hours / 24

        if days > 0 {
            return "\(days)일"
        } else if hours > 0 {
            return "\(hours)시간"
        } else {
            let minutes = Int(interval) / 60
            return "\(minutes)분"
        }
    }
}

// MARK: - Response Rate Bar
struct ResponseRateBar: View {
    let rating: Int
    let responded: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(responded) / Double(total)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rating)★")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            Text("\(responded)/\(total)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(String(format: "%.0f%%", percentage * 100))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Stats Item
struct StatsItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 24, weight: .bold))

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Rating Bar
struct RatingBar: View {
    let rating: Int
    let count: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rating)★")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(ratingColor(rating))
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    func ratingColor(_ rating: Int) -> Color {
        switch rating {
        case 5: return .green
        case 4: return .blue
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
