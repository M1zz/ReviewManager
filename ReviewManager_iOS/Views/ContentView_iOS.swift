//
//  ContentView_iOS.swift
//  ReviewManager (iOS)
//
//  iOS 메인 화면
//

import SwiftUI

struct ContentView_iOS: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView_iOS()
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            AppListView_iOS()
                .tabItem {
                    Label("앱", systemImage: "app.badge")
                }

            SettingsView_iOS()
                .tabItem {
                    Label("설정", systemImage: "gear")
                }
        }
        .task {
            if appState.apps.isEmpty {
                await appState.fetchApps()
            }
        }
    }
}

// MARK: - App List View
struct AppListView_iOS: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List(appState.apps) { app in
                NavigationLink(destination: ReviewListView_iOS(app: app)) {
                    AppRow_iOS(app: app)
                }
            }
            .navigationTitle("내 앱")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await appState.fetchApps()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                }
            }
            .overlay {
                if appState.isLoading {
                    ProgressView("로딩 중...")
                }
            }
        }
    }
}

// MARK: - App Row
struct AppRow_iOS: View {
    let app: AppInfo

    var body: some View {
        HStack(spacing: 12) {
            // 앱 아이콘
            if let iconURL = app.iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "app.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .frame(width: 60, height: 60)
                .cornerRadius(13)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(13)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 새 리뷰 뱃지
            if app.newReviewsCount > 0 {
                Text("\(app.newReviewsCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Review List View
struct ReviewListView_iOS: View {
    @EnvironmentObject var appState: AppState
    let app: AppInfo

    @State private var selectedFilter: ReviewFilter = .all
    @State private var searchText = ""
    @State private var showingFilterSheet = false

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

        return reviews.sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        List {
            if appState.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if filteredReviews.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("리뷰가 없습니다")
                        .font(.headline)

                    Text("선택한 필터에 해당하는 리뷰가 없습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(filteredReviews) { review in
                    NavigationLink(destination: ReviewDetailView_iOS(review: review)) {
                        ReviewRowView_iOS(review: review)
                    }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "리뷰 검색")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await appState.fetchReviews(for: app)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(appState.isLoading)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheet_iOS(selectedFilter: $selectedFilter)
        }
        .task {
            await appState.fetchReviews(for: app)
        }
    }
}

// MARK: - Review Row View
struct ReviewRowView_iOS: View {
    let review: CustomerReview

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.starsDisplay)
                    .foregroundColor(ratingColor)
                    .font(.subheadline)

                Spacer()

                Text(review.territory)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                if review.response != nil {
                    Image(systemName: "checkmark.bubble.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            if let title = review.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }

            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack {
                if let nickname = review.reviewerNickname {
                    Text(nickname)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(review.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Sheet
struct FilterSheet_iOS: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedFilter: ReviewFilter

    var body: some View {
        NavigationStack {
            List {
                Section("필터") {
                    ForEach(ReviewFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                            dismiss()
                        } label: {
                            HStack {
                                Text(filter.rawValue)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("필터 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }
}
