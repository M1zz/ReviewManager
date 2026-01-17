//
//  ContentView.swift
//  ReviewManageriOS
//
//  iOS 메인 뷰
//

import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        TabView {
            AppsListView()
                .tabItem {
                    Label("앱", systemImage: "app.fill")
                }

            SyncView()
                .tabItem {
                    Label("동기화", systemImage: "arrow.triangle.2.circlepath")
                }
        }
    }
}

// MARK: - 앱 목록 뷰
struct AppsListView: View {
    @EnvironmentObject var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AppEntity.name, ascending: true)],
        animation: .default)
    private var apps: FetchedResults<AppEntity>

    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive

    var filteredApps: [AppEntity] {
        let allApps = Array(apps)

        // 저장된 순서 적용
        let orderedApps = applySavedOrder(to: allApps)

        if searchText.isEmpty {
            return orderedApps
        } else {
            return orderedApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredApps, id: \.id) { app in
                    NavigationLink(destination: ReviewsListView(app: app)) {
                        AppRowView(app: app)
                    }
                }
                .onMove { source, destination in
                    moveApps(from: source, to: destination)
                }
            }
            .navigationTitle("내 앱")
            .searchable(text: $searchText, prompt: "앱 검색")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            await syncService.syncAll()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(syncService.isSyncing)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                await syncService.syncAll()
            }
            .overlay {
                if apps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("앱 정보가 없습니다")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("아래로 당겨서 동기화하세요")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // 저장된 순서 적용
    private func applySavedOrder(to apps: [AppEntity]) -> [AppEntity] {
        guard let savedOrder = UserDefaults.standard.array(forKey: "appOrderiOS") as? [String] else {
            // 저장된 순서가 없으면 이름순
            return apps.sorted { $0.name < $1.name }
        }

        var orderedApps: [AppEntity] = []
        var remainingApps = apps

        // 저장된 순서에 따라 배치
        for appID in savedOrder {
            if let index = remainingApps.firstIndex(where: { $0.id == appID }) {
                orderedApps.append(remainingApps.remove(at: index))
            }
        }

        // 새로 추가된 앱들은 이름순으로 마지막에 추가
        let newApps = remainingApps.sorted { $0.name < $1.name }
        orderedApps.append(contentsOf: newApps)

        return orderedApps
    }

    // 앱 순서 변경
    private func moveApps(from source: IndexSet, to destination: Int) {
        var orderedApps = filteredApps
        orderedApps.move(fromOffsets: source, toOffset: destination)

        // 순서 저장
        let appIDs = orderedApps.map { $0.id }
        UserDefaults.standard.set(appIDs, forKey: "appOrderiOS")
        print("✅ [iOS] 앱 순서 저장: \(appIDs)")
    }
}

// MARK: - 앱 행 뷰
struct AppRowView: View {
    let app: AppEntity

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
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
                .frame(width: 50, height: 50)
                .cornerRadius(10)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastSynced = app.lastSynced {
                    Text("최근 동기화: \(lastSynced, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 리뷰 개수
            let reviewCount = app.reviewsArray.count
            if reviewCount > 0 {
                VStack {
                    Text("\(reviewCount)")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text("리뷰")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 리뷰 목록 뷰
struct ReviewsListView: View {
    let app: AppEntity
    @State private var searchText = ""

    var filteredReviews: [ReviewEntity] {
        let reviews = app.reviewsArray
        if searchText.isEmpty {
            return reviews
        } else {
            return reviews.filter {
                ($0.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.body?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.reviewerNickname?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        List(filteredReviews, id: \.id) { review in
            NavigationLink(destination: ReviewDetailView(review: review)) {
                ReviewRowView(review: review)
            }
        }
        .navigationTitle(app.name)
        .searchable(text: $searchText, prompt: "리뷰 검색")
        .overlay {
            if app.reviewsArray.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("리뷰가 없습니다")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            } else if filteredReviews.isEmpty && !searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("검색 결과가 없습니다")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - 리뷰 행 뷰
struct ReviewRowView: View {
    let review: ReviewEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.starsDisplay)
                    .font(.subheadline)
                    .foregroundColor(.orange)

                Spacer()

                Text(review.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
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

                Text(review.territory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                if review.response != nil {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 리뷰 상세 뷰
struct ReviewDetailView: View {
    @EnvironmentObject var apiState: APIState
    @EnvironmentObject var syncService: SyncService

    let review: ReviewEntity

    @State private var showingResponseSheet = false
    @State private var showingDeleteAlert = false
    @State private var responseText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 리뷰 헤더
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(review.starsDisplay)
                            .font(.title2)
                            .foregroundColor(.orange)

                        Spacer()

                        Text(review.territory)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }

                    if let nickname = review.reviewerNickname {
                        Text(nickname)
                            .font(.headline)
                    }

                    Text(review.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                // 리뷰 내용
                VStack(alignment: .leading, spacing: 12) {
                    if let title = review.title, !title.isEmpty {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    if let body = review.body, !body.isEmpty {
                        Text(body)
                            .font(.body)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 2)

                // 개발자 응답
                if let response = review.response {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundColor(.green)
                            Text("개발자 응답")
                                .font(.headline)
                                .foregroundColor(.green)

                            Spacer()

                            Text(response.displayState)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(response.state == "PUBLISHED" ? Color.green : Color.orange)
                                .cornerRadius(6)
                        }

                        Text(response.responseBody)
                            .font(.body)

                        Text(response.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // 응답 액션 버튼
                        if apiState.isAuthenticated {
                            HStack(spacing: 12) {
                                Button(action: {
                                    responseText = response.responseBody
                                    showingResponseSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("수정")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }

                                Button(action: {
                                    showingDeleteAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("삭제")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                }
                            }
                        } else {
                            Text("⚠️ 응답 수정/삭제는 macOS 앱에서 가능합니다.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // 응답 추가 버튼
                    VStack(spacing: 12) {
                        Button(action: {
                            responseText = ""
                            showingResponseSheet = true
                        }) {
                            HStack {
                                Image(systemName: "arrowshape.turn.up.left")
                                Text("응답 작성하기")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(apiState.isAuthenticated ? Color.blue : Color.gray)
                            .cornerRadius(10)
                        }
                        .disabled(!apiState.isAuthenticated)

                        if !apiState.isAuthenticated {
                            Text("⚠️ API 인증 정보가 없습니다. macOS 앱에서 API 키를 설정하고 백업해주세요.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("리뷰 상세")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingResponseSheet) {
            ResponseSheet(
                reviewID: review.id,
                reviewTitle: review.title ?? "",
                reviewBody: review.body ?? "",
                initialResponse: responseText,
                isPresented: $showingResponseSheet
            )
        }
        .alert("응답 삭제", isPresented: $showingDeleteAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                Task {
                    await deleteResponse()
                }
            }
        } message: {
            Text("이 응답을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
        }
    }

    private func deleteResponse() async {
        guard let responseID = review.response?.id else { return }

        do {
            try await apiState.deleteResponse(responseID: responseID)
            await syncService.syncAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 응답 작성 시트
struct ResponseSheet: View {
    @EnvironmentObject var apiState: APIState
    @EnvironmentObject var syncService: SyncService

    let reviewID: String
    let reviewTitle: String
    let reviewBody: String
    let initialResponse: String
    @Binding var isPresented: Bool

    @State private var responseText = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 리뷰 미리보기
                VStack(alignment: .leading, spacing: 12) {
                    Text("리뷰 내용")
                        .font(.headline)

                    if !reviewTitle.isEmpty {
                        Text(reviewTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(reviewBody)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                // 응답 입력
                VStack(alignment: .leading, spacing: 8) {
                    Text("개발자 응답")
                        .font(.headline)

                    TextEditor(text: $responseText)
                        .frame(height: 150)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Text("\(responseText.count) / 5970자")
                        .font(.caption)
                        .foregroundColor(responseText.count > 5970 ? .red : .secondary)
                }

                if apiState.isLoading {
                    ProgressView("전송 중...")
                        .padding()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("응답 작성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        isPresented = false
                    }
                    .disabled(apiState.isLoading)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("전송") {
                        Task {
                            await sendResponse()
                        }
                    }
                    .disabled(responseText.isEmpty || responseText.count > 5970 || apiState.isLoading)
                }
            }
            .alert(isSuccess ? "성공" : "오류", isPresented: $showingAlert) {
                Button("확인", role: .cancel) {
                    if isSuccess {
                        isPresented = false
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                responseText = initialResponse
            }
        }
    }

    private func sendResponse() async {
        do {
            try await apiState.respondToReview(reviewID: reviewID, response: responseText)

            // 성공 시 동기화하여 최신 데이터 가져오기
            await syncService.syncAll()

            alertMessage = "응답이 성공적으로 전송되었습니다."
            isSuccess = true
            showingAlert = true
        } catch {
            alertMessage = "응답 전송 실패: \(error.localizedDescription)"
            isSuccess = false
            showingAlert = true
        }
    }
}

// MARK: - 동기화 뷰
struct SyncView: View {
    @EnvironmentObject var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AppEntity.name, ascending: true)],
        animation: .default)
    private var apps: FetchedResults<AppEntity>

    var totalReviews: Int {
        apps.reduce(0) { $0 + $1.reviewsArray.count }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("CloudKit 동기화")
                            .font(.title2)
                            .fontWeight(.bold)

                        if let lastSync = syncService.lastSyncDate {
                            Text("최근 동기화: \(lastSync, style: .relative)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("아직 동기화하지 않았습니다")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if syncService.isSyncing {
                            ProgressView()
                                .padding(.top, 8)

                            if !syncService.syncProgress.isEmpty {
                                Text(syncService.syncProgress)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            Button(action: {
                                Task {
                                    await syncService.syncAll()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("동기화 시작")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            .padding(.top, 8)
                        }

                        if let error = syncService.syncError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }

                Section(header: Text("설정")) {
                    Toggle(isOn: $syncService.autoSyncEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("자동 동기화")
                                .font(.body)
                            Text("30분마다 자동으로 동기화합니다")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("로컬 데이터")) {
                    HStack {
                        Text("앱 개수")
                        Spacer()
                        Text("\(apps.count)개")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("리뷰 개수")
                        Spacer()
                        Text("\(totalReviews)개")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("정보")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("이 앱은 읽기 전용입니다")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("macOS 앱에서 App Store Connect API를 통해 리뷰를 가져오고, CloudKit에 자동으로 업로드합니다. iOS 앱은 CloudKit에서 데이터를 동기화하여 보여줍니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("동기화")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncService.shared)
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
}
