//
//  OnboardingView.swift
//  ReviewManager
//
//  API 연결 설정 화면
//

import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentStep = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "star.bubble")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Review Manager")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("App Store 리뷰를 한곳에서 관리하세요")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)
            
            // 단계 표시
            StepIndicator(currentStep: currentStep)
                .padding(.bottom, 24)
            
            // 콘텐츠
            TabView(selection: $currentStep) {
                IntroStep()
                    .tag(0)
                
                IssuerIDStep(issuerID: $issuerID)
                    .tag(1)
                
                KeyIDStep(keyID: $keyID)
                    .tag(2)
                
                PrivateKeyStep(privateKey: $privateKey)
                    .tag(3)
                
                ConfirmStep(
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKey: privateKey,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )
                    .tag(4)
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: 600)
            
            Spacer()
            
            // 네비게이션 버튼
            HStack {
                if currentStep > 0 {
                    Button("이전") {
                        withAnimation {
                            currentStep -= 1
                            errorMessage = nil
                        }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }

                Spacer()

                if currentStep < 4 {
                    Button("다음") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
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

            // 데모 모드 진입 (인증 없이 전체 기능 체험)
            VStack(spacing: 4) {
                Divider()
                Button {
                    appState.enterDemoMode()
                } label: {
                    Label("데모 모드로 둘러보기", systemImage: "play.circle")
                }
                .buttonStyle(.link)
                .padding(.top, 8)

                Text("API 키 없이 샘플 데이터로 모든 기능을 체험할 수 있습니다")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 700, minHeight: 550)
    }
    
    var canProceed: Bool {
        switch currentStep {
        case 1: return !issuerID.isEmpty
        case 2: return !keyID.isEmpty
        case 3: return !privateKey.isEmpty
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
            do {
                await appState.fetchApps()
                if appState.errorMessage != nil {
                    errorMessage = appState.errorMessage
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Step Indicator
struct StepIndicator: View {
    let currentStep: Int
    let totalSteps = 5
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Intro Step
struct IntroStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("App Store Connect API 연결")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "app.badge.checkmark",
                    title: "앱 리뷰 통합 관리",
                    description: "모든 앱의 리뷰를 한 곳에서 확인"
                )
                
                FeatureRow(
                    icon: "arrowshape.turn.up.left.fill",
                    title: "빠른 응답",
                    description: "리뷰에 바로 응답 작성 및 관리"
                )
                
                FeatureRow(
                    icon: "chart.bar.fill",
                    title: "통계 확인",
                    description: "평점 및 응답률 한눈에 파악"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            Text("시작하려면 App Store Connect에서\nAPI 키를 생성해야 합니다.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Link(destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) {
                Label("App Store Connect 열기", systemImage: "arrow.up.right.square")
            }
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Issuer ID Step
struct IssuerIDStep: View {
    @Binding var issuerID: String
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Issuer ID 입력")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("App Store Connect > 사용자 및 액세스 > 통합 >\nApp Store Connect API에서 Issuer ID를 확인할 수 있습니다.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $issuerID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 Issuer ID 찾는 방법")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. App Store Connect 로그인")
                    Text("2. 사용자 및 액세스 클릭")
                    Text("3. 상단 '통합' 탭 선택")
                    Text("4. App Store Connect API 페이지 상단에서 Issuer ID 확인")
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

// MARK: - Key ID Step
struct KeyIDStep: View {
    @Binding var keyID: String
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Key ID 입력")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("생성한 API Key의 Key ID를 입력하세요.\n(10자리 영문+숫자 조합)")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                TextField("XXXXXXXXXX", text: $keyID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 API Key 생성 방법")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. App Store Connect > 사용자 및 액세스")
                    Text("2. 상단 '통합' 탭 클릭")
                    Text("3. App Store Connect API 선택")
                    Text("4. '팀 키' 탭에서 '+' 또는 'API 키 생성' 클릭")
                    Text("5. 이름 입력 및 '관리(Admin)' 권한 선택")
                    Text("6. 생성된 키 목록에서 Key ID 복사")
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

// MARK: - Private Key Step
struct PrivateKeyStep: View {
    @Binding var privateKey: String
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Private Key (.p8) 입력")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key 생성 후 다운로드한 .p8 파일의 내용을 붙여넣거나\n파일을 드래그하세요.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                ZStack {
                    TextEditor(text: $privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isDragging ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isDragging ? 2 : 1)
                        )
                    
                    if privateKey.isEmpty {
                        VStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text(".p8 파일을 드래그하거나 내용을 붙여넣으세요")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    guard let provider = providers.first else { return false }
                    
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                        guard let data = data as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              let content = try? String(contentsOf: url, encoding: .utf8) else {
                            return
                        }
                        
                        DispatchQueue.main.async {
                            privateKey = content
                        }
                    }
                    return true
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠️ 중요 안내")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• .p8 파일은 생성 직후 한 번만 다운로드 가능합니다")
                    Text("• 다운로드 후 안전한 곳에 보관하세요")
                    Text("• Private Key는 로컬에만 저장되며 외부로 전송되지 않습니다")
                }
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

// MARK: - Confirm Step
struct ConfirmStep: View {
    let issuerID: String
    let keyID: String
    let privateKey: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("설정 확인")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                ConfirmRow(title: "Issuer ID", value: issuerID, isValid: !issuerID.isEmpty)
                ConfirmRow(title: "Key ID", value: keyID, isValid: !keyID.isEmpty)
                ConfirmRow(
                    title: "Private Key",
                    value: privateKey.isEmpty ? "없음" : "✓ 입력됨 (\(privateKey.count)자)",
                    isValid: !privateKey.isEmpty
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            if isLoading {
                ProgressView("연결 중...")
            }

            if let error = errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("❌ 연결 실패")
                                .font(.headline)
                                .foregroundColor(.red)

                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    if error.contains("Private Key") || error.contains(".p8") || error.contains("서명") {
                        Text("💡 Private Key를 다시 확인해주세요")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Text("• .p8 파일 전체 내용을 복사했는지 확인\n• -----BEGIN PRIVATE KEY----- 로 시작하는지 확인\n• -----END PRIVATE KEY----- 로 끝나는지 확인")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            if errorMessage == nil {
                Text("'연결하기' 버튼을 클릭하면\nApp Store Connect API에 연결을 시도합니다.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

struct ConfirmRow: View {
    let title: String
    let value: String
    let isValid: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isValid ? .green : .red)
            
            Text(title)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
