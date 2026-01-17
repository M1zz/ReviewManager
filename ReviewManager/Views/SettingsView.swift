//
//  SettingsView.swift
//  ReviewManager
//
//  설정 화면
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var showPrivateKey = false
    @State private var showingLogoutAlert = false
    
    var body: some View {
        TabView {
            // API 설정
            APISettingsTab(
                issuerID: $issuerID,
                keyID: $keyID,
                privateKey: $privateKey,
                showPrivateKey: $showPrivateKey,
                showingLogoutAlert: $showingLogoutAlert
            )
            .tabItem {
                Label("API", systemImage: "key")
            }
            
            // 일반 설정
            GeneralSettingsTab()
                .tabItem {
                    Label("일반", systemImage: "gear")
                }
            
            // 정보
            AboutTab()
                .tabItem {
                    Label("정보", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 500)
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
    
    func loadSettings() {
        issuerID = UserDefaults.standard.string(forKey: "issuerID") ?? ""
        keyID = UserDefaults.standard.string(forKey: "keyID") ?? ""
        privateKey = UserDefaults.standard.string(forKey: "privateKey") ?? ""
    }
}

// MARK: - API Settings Tab
struct APISettingsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var issuerID: String
    @Binding var keyID: String
    @Binding var privateKey: String
    @Binding var showPrivateKey: Bool
    @Binding var showingLogoutAlert: Bool

    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Issuer ID", text: $issuerID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditing)

                TextField("Key ID", text: $keyID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditing)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showPrivateKey {
                            TextEditor(text: $privateKey)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 100)
                                .disabled(!isEditing)
                        } else {
                            SecureField("Private Key", text: $privateKey)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!isEditing)
                        }

                        VStack {
                            Button {
                                showPrivateKey.toggle()
                            } label: {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                            }

                            Spacer()
                        }
                    }

                    if isEditing {
                        Text("💡 .p8 파일의 전체 내용을 붙여넣으세요\n(-----BEGIN PRIVATE KEY----- 부터 -----END PRIVATE KEY----- 까지)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text("App Store Connect API")
            } footer: {
                if let message = saveMessage {
                    Text(message)
                        .foregroundColor(message.contains("성공") ? .green : .red)
                } else if !isEditing {
                    Text("API 설정을 변경하려면 '편집' 버튼을 클릭하세요.")
                }
            }

            Section {
                HStack {
                    Spacer()

                    if isEditing {
                        Button("취소") {
                            isEditing = false
                            saveMessage = nil
                            loadOriginalSettings()
                        }

                        Button("저장") {
                            saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || issuerID.isEmpty || keyID.isEmpty || privateKey.isEmpty)
                    } else {
                        Button("편집") {
                            isEditing = true
                            saveMessage = nil
                        }
                        .buttonStyle(.bordered)

                        Button("로그아웃") {
                            showingLogoutAlert = true
                        }
                        .foregroundColor(.red)
                    }

                    Spacer()
                }
            }

            if isSaving {
                HStack {
                    Spacer()
                    ProgressView("연결 테스트 중...")
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    func loadOriginalSettings() {
        issuerID = UserDefaults.standard.string(forKey: "issuerID") ?? ""
        keyID = UserDefaults.standard.string(forKey: "keyID") ?? ""
        privateKey = UserDefaults.standard.string(forKey: "privateKey") ?? ""
    }

    func saveSettings() {
        isSaving = true
        saveMessage = nil

        appState.configure(issuerID: issuerID, keyID: keyID, privateKey: privateKey)

        Task {
            do {
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
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("refreshInterval") private var refreshInterval = 5
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("showUnrespondedOnly") private var showUnrespondedOnly = false

    var body: some View {
        Form {
            Section {
                Picker("자동 새로고침 간격", selection: $refreshInterval) {
                    Text("사용 안 함").tag(0)
                    Text("5분").tag(5)
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("1시간").tag(60)
                }
            } header: {
                Text("새로고침")
            }

            Section {
                Toggle("알림 활성화", isOn: $notificationsEnabled)
                Toggle("미응답 리뷰만 표시", isOn: $showUnrespondedOnly)
            } header: {
                Text("기본 설정")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("iCloud 동기화", isOn: $appState.iCloudSyncEnabled)

                    if appState.iCloudSyncEnabled {
                        Text("리뷰를 조회할 때마다 자동으로 iCloud에 백업됩니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task {
                                await appState.backupAllToCloudKit()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                Text("지금 백업하기")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isBackingUp || appState.apps.isEmpty)

                        if appState.isBackingUp {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                if let progress = appState.backupProgress {
                                    Text(progress)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else if let progress = appState.backupProgress {
                            Text(progress)
                                .font(.caption)
                                .foregroundColor(progress.contains("✅") ? .green : .red)
                        }

                        Text("💡 모든 앱의 리뷰를 CloudKit에 백업합니다. iOS 앱에서 동기화하여 확인할 수 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("CloudKit 백업")
            } footer: {
                Text("iCloud에 로그인되어 있어야 합니다.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.bubble")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Review Manager")
                .font(.title)
                .fontWeight(.bold)
            
            Text("버전 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 50)
            
            VStack(spacing: 8) {
                Text("App Store 리뷰를 편리하게 관리하세요")
                    .font(.callout)
                
                Link("App Store Connect API 문서", destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi")!)
                    .font(.caption)
            }
            
            Spacer()
            
            Text("Made with ❤️ for Indie Developers")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
