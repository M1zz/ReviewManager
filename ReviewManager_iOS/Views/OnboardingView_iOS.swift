//
//  OnboardingView_iOS.swift
//  ReviewManager (iOS)
//
//  iOS 온보딩 화면
//

import SwiftUI

struct OnboardingView_iOS: View {
    @EnvironmentObject var appState: AppState

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var currentStep = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 헤더
                VStack(spacing: 16) {
                    Image(systemName: "star.bubble")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)

                    Text("Review Manager")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("App Store 리뷰를 한곳에서 관리하세요")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.bottom, 32)

                // 단계 표시
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 24)

                // 콘텐츠
                TabView(selection: $currentStep) {
                    IntroStep_iOS()
                        .tag(0)

                    IssuerIDStep_iOS(issuerID: $issuerID)
                        .tag(1)

                    KeyIDStep_iOS(keyID: $keyID)
                        .tag(2)

                    PrivateKeyStep_iOS(privateKey: $privateKey)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Spacer()

                // 에러 메시지
                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("❌ 연결 실패")
                            .font(.headline)
                            .foregroundColor(.red)

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if error.contains("Private Key") || error.contains(".p8") || error.contains("서명") {
                            Text("💡 Private Key를 다시 확인해주세요")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // 네비게이션 버튼
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("이전") {
                            withAnimation {
                                currentStep -= 1
                                errorMessage = nil
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if currentStep < 3 {
                        Button("다음") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canProceed)
                    } else {
                        Button("연결하기") {
                            connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canConnect || isLoading)
                    }
                }
                .padding()
            }
        }
    }

    var canProceed: Bool {
        switch currentStep {
        case 1: return !issuerID.isEmpty
        case 2: return !keyID.isEmpty
        default: return true
        }
    }

    var canConnect: Bool {
        !issuerID.isEmpty && !keyID.isEmpty && !privateKey.isEmpty
    }

    func connect() {
        isLoading = true
        errorMessage = nil

        appState.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)

        Task {
            await appState.fetchApps()

            await MainActor.run {
                if appState.errorMessage != nil {
                    errorMessage = appState.errorMessage
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Intro Step
struct IntroStep_iOS: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("시작하기")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow_iOS(
                        icon: "app.badge.checkmark",
                        title: "앱 리뷰 통합 관리",
                        description: "모든 앱의 리뷰를 한 곳에서 확인"
                    )

                    FeatureRow_iOS(
                        icon: "arrowshape.turn.up.left.fill",
                        title: "빠른 응답",
                        description: "리뷰에 바로 응답 작성 및 관리"
                    )

                    FeatureRow_iOS(
                        icon: "icloud",
                        title: "iCloud 동기화",
                        description: "macOS 앱과 데이터 자동 동기화"
                    )
                }

                Link("App Store Connect 열기", destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!)
                    .font(.callout)
            }
            .padding()
        }
    }
}

struct FeatureRow_iOS: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Issuer ID Step
struct IssuerIDStep_iOS: View {
    @Binding var issuerID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Issuer ID 입력")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $issuerID)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 Issuer ID 찾는 방법")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. App Store Connect 로그인")
                        Text("2. 사용자 및 액세스 클릭")
                        Text("3. 상단 '통합' 탭 선택")
                        Text("4. App Store Connect API 페이지 상단에서 확인")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - Key ID Step
struct KeyIDStep_iOS: View {
    @Binding var keyID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Key ID 입력")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextField("XXXXXXXXXX", text: $keyID)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 API Key 생성 방법")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. App Store Connect > 사용자 및 액세스")
                        Text("2. 상단 '통합' 탭 클릭")
                        Text("3. API 키 생성")
                        Text("4. '관리(Admin)' 권한 선택")
                        Text("5. Key ID 복사")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - Private Key Step
struct PrivateKeyStep_iOS: View {
    @Binding var privateKey: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Private Key 입력")
                    .font(.title2)
                    .fontWeight(.semibold)

                TextEditor(text: $privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 .p8 파일의 전체 내용을 붙여넣으세요")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("• -----BEGIN PRIVATE KEY----- 로 시작\n• -----END PRIVATE KEY----- 로 끝남\n• Private Key는 로컬에만 저장")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}
