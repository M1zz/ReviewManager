# Review Manager - Xcode 프로젝트 설정 가이드

## 🚀 빠른 시작

### 1단계: iOS 타겟 생성

1. Xcode에서 `ReviewManager.xcodeproj` 열기
2. 프로젝트 네비게이터에서 최상단 프로젝트 클릭
3. 하단 "+" 버튼 → "Target" 추가
4. **iOS** → **App** 선택
5. 설정:
   - Product Name: `ReviewManager iOS`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Bundle Identifier: `com.[YourTeam].ReviewManager-iOS`

### 2단계: 파일 타겟 설정

#### macOS + iOS 공유 파일 (양쪽 타겟 모두 체크)

다음 파일들을 선택하고 우측 Inspector에서 **양쪽 타겟 모두 체크**:

**필수 공유 파일:**
```
✅ Models/Models.swift
✅ Services/AppStoreConnectService.swift
✅ Services/CloudKitService.swift
✅ Services/iTunesSearchService.swift
✅ AppState.swift
```

**방법:**
1. 파일 선택
2. 우측 File Inspector (⌥⌘1)
3. "Target Membership" 섹션
4. macOS와 iOS 타겟 모두 체크

#### macOS 전용 파일

```
✅ ReviewManagerApp.swift (macOS만)
✅ Views/ContentView.swift
✅ Views/OnboardingView.swift
✅ Views/SettingsView.swift
```

#### iOS 전용 파일

```
✅ ReviewManager_iOS/ReviewManagerApp_iOS.swift
✅ ReviewManager_iOS/Views/ContentView_iOS.swift
✅ ReviewManager_iOS/Views/OnboardingView_iOS.swift
✅ ReviewManager_iOS/Views/ReviewDetailView_iOS.swift
✅ ReviewManager_iOS/Views/SettingsView_iOS.swift
```

### 3단계: CloudKit 설정

#### macOS 타겟:
1. 타겟 선택 → Signing & Capabilities
2. "+ Capability" → "iCloud" 추가
3. Services: ✅ CloudKit
4. Containers: "+ Container" → 새 Container 생성
   - Identifier: `iCloud.com.[YourTeam].ReviewManager`

#### iOS 타겟:
1. **동일한 과정 반복**
2. ⚠️ **중요:** macOS와 **동일한 Container ID** 사용

### 4단계: Bundle Identifier 설정

- **macOS:** `com.[YourTeam].ReviewManager`
- **iOS:** `com.[YourTeam].ReviewManager-iOS`

### 5단계: App Sandbox (macOS)

macOS 타겟 → Signing & Capabilities → App Sandbox:
- ✅ Outgoing Connections (Network)

### 6단계: 빌드 및 실행

#### macOS:
```
타겟: ReviewManager (macOS)
⌘R (Run)
```

#### iOS:
```
타겟: ReviewManager iOS
시뮬레이터 또는 실제 기기 선택
⌘R (Run)
```

## 📁 최종 프로젝트 구조

```
ReviewManager.xcodeproj
│
├── ReviewManager/ (macOS)
│   ├── ReviewManagerApp.swift
│   ├── AppState.swift ✅ 공유
│   ├── Models/
│   │   └── Models.swift ✅ 공유
│   ├── Services/
│   │   ├── AppStoreConnectService.swift ✅ 공유
│   │   ├── CloudKitService.swift ✅ 공유
│   │   └── iTunesSearchService.swift ✅ 공유
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── OnboardingView.swift
│   │   └── SettingsView.swift
│   └── Assets.xcassets/
│
└── ReviewManager_iOS/ (iOS)
    ├── ReviewManagerApp_iOS.swift
    └── Views/
        ├── ContentView_iOS.swift
        ├── OnboardingView_iOS.swift
        ├── ReviewDetailView_iOS.swift
        └── SettingsView_iOS.swift
```

## ⚠️ 자주 발생하는 에러

### 1. "Cannot find 'AppState' in scope"
**원인:** AppState.swift가 타겟에 포함되지 않음
**해결:** AppState.swift를 양쪽 타겟에 추가

### 2. "Cannot find type 'AppInfo' in scope"
**원인:** Models.swift가 타겟에 포함되지 않음
**해결:** Models.swift를 양쪽 타겟에 추가

### 3. CloudKit 에러
**원인:** iCloud Capability 설정 안 됨 또는 Container ID 불일치
**해결:**
- 양쪽 타겟에 iCloud Capability 추가
- 동일한 Container ID 사용 확인

### 4. "Ambiguous use of..."
**원인:** 같은 이름의 파일이 여러 타겟에 중복
**해결:** macOS 전용 파일은 macOS만, iOS 전용은 iOS만 체크

## 🎯 테스트 체크리스트

- [ ] macOS 앱 빌드 성공
- [ ] iOS 앱 빌드 성공
- [ ] API 키 설정 (macOS)
- [ ] iCloud 동기화 후 iOS에서 자동 로드
- [ ] 앱 목록 조회
- [ ] 앱 아이콘 표시
- [ ] 리뷰 목록 조회
- [ ] 새 리뷰 뱃지 표시
- [ ] 리뷰 응답 작성

## 🔧 추가 설정 (선택사항)

### Info.plist 권한 (필요시)
iOS Info.plist:
```xml
<key>NSCloudKitSharingSupported</key>
<true/>
```

### 아이콘 추가
- macOS: `Assets.xcassets/AppIcon.appiconset/`
- iOS: `Assets.xcassets/AppIcon.appiconset/`

## 📝 참고

- iTunes Search API는 인증 없이 사용 가능
- CloudKit은 무료 (제한 내)
- App Store Connect API는 무료

## 🆘 도움이 필요하면

이슈 생성: [GitHub Issues](https://github.com/your-repo/issues)
