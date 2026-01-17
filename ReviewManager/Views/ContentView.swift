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
            // 메인: 리뷰 목록
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
                    ProgressView("리뷰를 불러오는 중...")
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
        }
        .sheet(isPresented: $showingResponseSheet) {
            if let review = selectedReview {
                ResponseSheet(review: review)
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
                    Task {
                        await appState.fetchReviews(for: app)
                    }
                }
            }
        )) {
            Section {
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

                        // 새 리뷰 뱃지
                        if app.newReviewsCount > 0 {
                            Text("\(app.newReviewsCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
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
                            selectedReview = review
                            showingResponseSheet = true
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
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("리뷰 응답")
                    .font(.headline)
                Spacer()
                Button("취소") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                            TextEditor(text: $responseText)
                                .font(.body)
                                .frame(minHeight: 150)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            
                            HStack {
                                Text("\(responseText.count) / 5970")
                                    .font(.caption)
                                    .foregroundColor(responseText.count > 5970 ? .red : .secondary)
                                
                                Spacer()
                                
                                Button("전송") {
                                    Task {
                                        await appState.respondToReview(review, response: responseText)
                                        dismiss()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(responseText.isEmpty || responseText.count > 5970 || appState.isLoading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if let existingResponse = review.response {
                responseText = existingResponse.responseBody
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
