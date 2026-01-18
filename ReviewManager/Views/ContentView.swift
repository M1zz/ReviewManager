//
//  ContentView.swift
//  ReviewManager
//
//  메인 화면
//

import SwiftUI

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
                } else if appState.apps.isEmpty {
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

                ForEach(appState.apps) { app in
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
                    .tag(app)
                    .padding(.vertical, 4)
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
        }
        .listStyle(.sidebar)
        .navigationTitle("Review Manager")
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
                Button {
                    Task {
                        await appState.fetchApps()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("앱 목록 새로고침")
                .disabled(isEditMode)
            }
        }
        .task {
            if appState.apps.isEmpty {
                await appState.fetchApps()
            }
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
                }
                .padding()
                .background(Color.accentColor.opacity(0.05))
                .cornerRadius(8)
            }
            
            // 액션 버튼
            HStack {
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
                    GroupBox("원본 리뷰") {
                        VStack(alignment: .leading, spacing: 8) {
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

// MARK: - Statistics View
struct StatisticsView: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 다운로드 통계
                DownloadStatsCard(app: app)

                // 리뷰 통계
                ReviewStatsCard(reviews: appState.reviews)

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

// MARK: - Review Statistics Card
struct ReviewStatsCard: View {
    let reviews: [CustomerReview]

    var averageRating: Double {
        guard !reviews.isEmpty else { return 0 }
        let sum = reviews.reduce(0) { $0 + $1.rating }
        return Double(sum) / Double(reviews.count)
    }

    var responseRate: Double {
        guard !reviews.isEmpty else { return 0 }
        let respondedCount = reviews.filter { $0.response != nil }.count
        return Double(respondedCount) / Double(reviews.count) * 100
    }

    var ratingDistribution: [Int: Int] {
        var distribution: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for review in reviews {
            distribution[review.rating, default: 0] += 1
        }
        return distribution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("리뷰 통계", systemImage: "star.bubble.fill")
                .font(.headline)

            Divider()

            if reviews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("아직 리뷰가 없습니다")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 20) {
                    // 요약 정보
                    HStack(spacing: 30) {
                        StatsItem(
                            title: "평균 평점",
                            value: String(format: "%.1f", averageRating),
                            icon: "star.fill",
                            color: .yellow
                        )

                        StatsItem(
                            title: "총 리뷰",
                            value: "\(reviews.count)",
                            icon: "text.bubble.fill",
                            color: .blue
                        )

                        StatsItem(
                            title: "응답률",
                            value: String(format: "%.0f%%", responseRate),
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }

                    Divider()

                    // 평점 분포
                    VStack(alignment: .leading, spacing: 8) {
                        Text("평점 분포")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

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
