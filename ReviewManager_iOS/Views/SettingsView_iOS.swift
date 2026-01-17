//
//  SettingsView_iOS.swift
//  ReviewManager (iOS)
//
//  iOS 설정 화면
//

import SwiftUI

struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppState

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var showPrivateKey = false
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showingLogoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                // API 설정 섹션
                Section {
                    if isEditing {
                        TextField("Issuer ID", text: $issuerID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Key ID", text: $keyID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        VStack(alignment: .leading, spacing: 8) {
                            if showPrivateKey {
                                TextEditor(text: $privateKey)
                                    .frame(height: 120)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                SecureField("Private Key", text: $privateKey)
                            }

                            HStack {
                                Button {
                                    showPrivateKey.toggle()
                                } label: {
                                    Label(
                                        showPrivateKey ? "키 숨기기" : "키 표시",
                                        systemImage: showPrivateKey ? "eye.slash" : "eye"
                                    )
                                    .font(.caption)
                                }

                                Spacer()
                            }

                            Text("💡 .p8 파일의 전체 내용을 붙여넣으세요")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        LabeledContent("Issuer ID", value: maskString(issuerID))
                        LabeledContent("Key ID", value: maskString(keyID))
                        LabeledContent("Private Key", value: privateKey.isEmpty ? "없음" : "✓ 설정됨")
                    }
                } header: {
                    Text("App Store Connect API")
                } footer: {
                    if let message = saveMessage {
                        Text(message)
                            .foregroundColor(message.contains("성공") ? .green : .red)
                    } else if !isEditing {
                        Text("API 설정을 변경하려면 '편집' 버튼을 탭하세요.")
                    }
                }

                // iCloud 동기화
                Section {
                    Toggle("iCloud 동기화", isOn: $appState.iCloudSyncEnabled)
                } header: {
                    Text("동기화")
                } footer: {
                    Text("iCloud를 통해 macOS 앱과 데이터를 동기화합니다.")
                }

                // 앱 정보
                Section {
                    LabeledContent("버전", value: "1.0.0")
                    Link("App Store Connect API 문서", destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi")!)
                } header: {
                    Text("정보")
                }

                // 액션
                Section {
                    if isEditing {
                        Button("취소") {
                            isEditing = false
                            saveMessage = nil
                            loadSettings()
                        }

                        Button("저장") {
                            saveSettings()
                        }
                        .disabled(isSaving || issuerID.isEmpty || keyID.isEmpty || privateKey.isEmpty)
                    } else {
                        Button("편집") {
                            isEditing = true
                            saveMessage = nil
                        }

                        Button("로그아웃", role: .destructive) {
                            showingLogoutAlert = true
                        }
                    }
                }

                if isSaving {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("연결 테스트 중...")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .onAppear {
                loadSettings()
            }
            .alert("로그아웃", isPresented: $showingLogoutAlert) {
                Button("취소", role: .cancel) { }
                Button("로그아웃", role: .destructive) {
                    appState.logout()
                }
            } message: {
                Text("저장된 API 인증 정보가 삭제됩니다.\n계속하시겠습니까?")
            }
        }
    }

    func maskString(_ string: String) -> String {
        guard !string.isEmpty else { return "없음" }
        let visible = min(8, string.count)
        let prefix = string.prefix(visible)
        return "\(prefix)..."
    }

    func loadSettings() {
        issuerID = UserDefaults.standard.string(forKey: "issuerID") ?? ""
        keyID = UserDefaults.standard.string(forKey: "keyID") ?? ""
        privateKey = UserDefaults.standard.string(forKey: "privateKey") ?? ""
    }

    func saveSettings() {
        isSaving = true
        saveMessage = nil

        appState.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)

        Task {
            await appState.fetchApps()

            await MainActor.run {
                if let error = appState.errorMessage {
                    saveMessage = "❌ 연결 실패: \(error)"
                    isSaving = false
                } else {
                    saveMessage = "✅ 저장 및 연결 성공!"
                    isEditing = false
                    isSaving = false

                    // 3초 후 메시지 제거
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        saveMessage = nil
                    }
                }
            }
        }
    }
}
