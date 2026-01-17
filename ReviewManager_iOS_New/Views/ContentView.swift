//
//  ContentView.swift
//  ReviewManager iOS
//
//  메인 화면 (읽기 전용)
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var syncService: SyncService

    var body: some View {
        TabView {
            AppsListView()
                .tabItem {
                    Label("앱", systemImage: "app.badge")
                }

            SyncView()
                .tabItem {
                    Label("동기화", systemImage: "arrow.triangle.2.circlepath")
                }
        }
    }
}

// MARK: - Apps List View
struct AppsListView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var apps: [AppInfo] = []

    var body: some View {
        NavigationStack {
            List(apps) { app in
                NavigationLink(destination: ReviewsListView(app: app)) {
                    AppRow(app: app)
                }
            }
            .navigationTitle("내 앱")
            .refreshable {
                await syncService.syncAll()
                loadApps()
            }
            .onAppear {
                loadApps()
            }
            .overlay {
                if apps.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("앱이 없습니다")
                            .font(.headline)

                        Text("아래로 당겨서 동기화하거나\n'동기화' 탭에서 데이터를 가져오세요")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            Task {
                                await syncService.syncAll()
                                loadApps()
                            }
                        } label: {
                            Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
    }

    func loadApps() {
        apps = syncService.fetchLocalApps()
    }
}

// MARK: - App Row
struct AppRow: View {
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reviews List View
struct ReviewsListView: View {
    @EnvironmentObject var syncService: SyncService
    let app: AppInfo

    @State private var reviews: [CustomerReview] = []
    @State private var searchText = ""

    var filteredReviews: [CustomerReview] {
        if searchText.isEmpty {
            return reviews
        } else {
            return reviews.filter { review in
                let searchLower = searchText.lowercased()
                return (review.title?.lowercased().contains(searchLower) ?? false) ||
                       (review.body?.lowercased().contains(searchLower) ?? false) ||
                       (review.reviewerNickname?.lowercased().contains(searchLower) ?? false)
            }
        }
    }

    var body: some View {
        List(filteredReviews) { review in
            NavigationLink(destination: ReviewDetailView(review: review)) {
                ReviewRow(review: review)
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "리뷰 검색")
        .refreshable {
            await syncService.syncReviews(for: app)
            loadReviews()
        }
        .onAppear {
            loadReviews()
        }
        .overlay {
            if filteredReviews.isEmpty && !searchText.isEmpty {
                Text("검색 결과가 없습니다")
                    .foregroundColor(.secondary)
            } else if reviews.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("리뷰가 없습니다")
                        .font(.headline)

                    Button {
                        Task {
                            await syncService.syncReviews(for: app)
                            loadReviews()
                        }
                    } label: {
                        Label("동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    func loadReviews() {
        reviews = syncService.fetchLocalReviews(appID: app.id)
    }
}

// MARK: - Review Row
struct ReviewRow: View {
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

// MARK: - Review Detail View
struct ReviewDetailView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 리뷰 정보
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(review.starsDisplay)
                            .font(.title2)
                            .foregroundColor(ratingColor)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(review.territory)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(6)

                            Text(review.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let title = review.title, !title.isEmpty {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    if let body = review.body, !body.isEmpty {
                        Text(body)
                            .font(.body)
                    }

                    if let nickname = review.reviewerNickname {
                        Text("— \(nickname)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5)

                // 개발자 응답
                if let response = review.response {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundColor(.accentColor)

                            Text("개발자 응답")
                                .font(.headline)

                            Spacer()

                            Text(response.state.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    response.state == .published
                                        ? Color.green.opacity(0.2)
                                        : Color.orange.opacity(0.2)
                                )
                                .cornerRadius(4)
                        }

                        Text(response.responseBody)
                            .font(.body)

                        Text(response.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(12)
                }

                // 읽기 전용 안내
                Text("💡 iOS 앱은 읽기 전용입니다. 응답을 작성하려면 macOS 앱을 사용하세요.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("리뷰 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sync View
struct SyncView: View {
    @EnvironmentObject var syncService: SyncService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let lastSync = syncService.lastSyncDate {
                        LabeledContent("마지막 동기화", value: formatDate(lastSync))
                    } else {
                        Text("아직 동기화하지 않았습니다")
                            .foregroundColor(.secondary)
                    }

                    if syncService.isSyncing {
                        HStack {
                            ProgressView()
                            Text("동기화 중...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button {
                            Task {
                                await syncService.syncAll()
                            }
                        } label: {
                            Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    Text("CloudKit 동기화")
                } footer: {
                    Text("macOS 앱에서 업로드한 리뷰 데이터를 가져옵니다.")
                }

                if let error = syncService.syncError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } header: {
                        Text("오류")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ℹ️ 사용 방법")
                            .font(.headline)

                        Text("1. macOS 앱에서 리뷰 조회")
                        Text("2. iOS 앱에서 '지금 동기화' 버튼 탭")
                        Text("3. CloudKit에서 데이터 다운로드")
                        Text("4. 로컬에 저장되어 오프라인에서도 확인 가능")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("도움말")
                }
            }
            .navigationTitle("동기화")
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
