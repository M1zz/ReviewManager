# Review Manager - iOS 앱 설정 가이드

## 🎯 새로운 아키텍처

```
┌─────────────────┐
│   macOS 앱      │
│  (쓰기/읽기)    │
└────────┬────────┘
         │
         │ App Store Connect API
         ↓
    [리뷰 데이터]
         │
         │ CloudKit 업로드
         ↓
┌─────────────────┐
│   CloudKit      │
│  (클라우드 저장소)│
└────────┬────────┘
         │
         │ 동기화
         ↓
┌─────────────────┐
│   iOS 앱        │
│  (읽기 전용)    │
│  ↓              │
│ CoreData (로컬)  │
└─────────────────┘
```

## 📱 iOS 앱 특징

- ✅ **읽기 전용**: 리뷰 조회만 가능
- ✅ **CloudKit 동기화**: macOS 앱에서 업로드한 데이터 자동 가져오기
- ✅ **로컬 저장**: CoreData에 저장되어 오프라인에서도 확인 가능
- ✅ **실제 앱 아이콘**: iTunes Search API로 자동 표시
- ✅ **검색 기능**: 리뷰 제목, 본문, 작성자 검색

## 🚀 Xcode 프로젝트 설정

### 1단계: iOS 타겟 생성

1. Xcode에서 `ReviewManager.xcodeproj` 열기
2. 프로젝트 선택 → 하단 "+" → "Target" 추가
3. **iOS** → **App** 선택
4. 설정:
   - Product Name: `ReviewManager iOS`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Bundle Identifier: `com.[YourTeam].ReviewManager-iOS`

### 2단계: 파일 추가

**iOS 전용 파일 (ReviewManager_iOS_New/):**

```
✅ ReviewManagerApp.swift
✅ Models/CoreDataModels.swift
✅ Services/PersistenceController.swift
✅ Services/SyncService.swift
✅ Views/ContentView.swift
```

**방법:**
1. Xcode 프로젝트 네비게이터에서 iOS 타겟 폴더 우클릭
2. "Add Files to..." 선택
3. `ReviewManager_iOS_New/` 폴더 전체 선택
4. **Options:**
   - ❌ "Copy items if needed" 체크 해제
   - ✅ "Create groups" 선택
   - ✅ "Add to targets": **ReviewManager iOS만** 체크

### 3단계: 공유 파일 타겟 추가

다음 파일들을 iOS 타겟에도 추가:

```
✅ ReviewManager/Models/Models.swift
✅ ReviewManager/Services/CloudKitService.swift
```

**방법:**
1. 해당 파일 선택
2. 우측 File Inspector (⌥⌘1)
3. "Target Membership"에서 **ReviewManager iOS** 체크

### 4단계: CloudKit Capability

**iOS 타겟:**
1. Signing & Capabilities 탭
2. "+ Capability" → "iCloud" 추가
3. Services: ✅ CloudKit
4. Containers: **macOS와 동일한 Container** 선택
   - `iCloud.com.[YourTeam].ReviewManager`

⚠️ **중요:** macOS와 **반드시 동일한 Container ID** 사용!

### 5단계: Bundle Identifier

- **macOS:** `com.[YourTeam].ReviewManager`
- **iOS:** `com.[YourTeam].ReviewManager-iOS`

## 📁 최종 프로젝트 구조

```
ReviewManager.xcodeproj
│
├── ReviewManager/ (macOS - 그대로)
│   ├── ReviewManagerApp.swift
│   ├── AppState.swift
│   ├── Models/
│   │   └── Models.swift ✅ macOS + iOS 공유
│   ├── Services/
│   │   ├── AppStoreConnectService.swift (macOS만)
│   │   ├── CloudKitService.swift ✅ macOS + iOS 공유
│   │   └── iTunesSearchService.swift (macOS만)
│   └── Views/ (macOS만)
│
└── ReviewManager_iOS_New/ (iOS - 새로 추가)
    ├── ReviewManagerApp.swift
    ├── Models/
    │   └── CoreDataModels.swift
    ├── Services/
    │   ├── PersistenceController.swift
    │   └── SyncService.swift
    └── Views/
        └── ContentView.swift
```

## 🎮 사용 방법

### macOS 앱 (관리자용)

1. App Store Connect API 키 설정
2. 앱 목록 조회
3. 리뷰 조회 → **자동으로 CloudKit에 업로드**
4. 리뷰에 응답 작성/수정/삭제

### iOS 앱 (확인용)

1. 앱 실행
2. **"동기화" 탭**으로 이동
3. **"지금 동기화"** 버튼 탭
4. CloudKit에서 데이터 다운로드 → CoreData에 저장
5. **"앱" 탭**에서 리뷰 확인
6. 오프라인에서도 저장된 리뷰 열람 가능

## 🔄 데이터 흐름

### macOS → CloudKit

```swift
// macOS 앱에서 리뷰 조회 시 자동 업로드
await appState.fetchReviews(for: app)
  ↓
CloudKitService.saveApp(app)
CloudKitService.saveReview(review, appID)
  ↓
CloudKit Private Database
```

### CloudKit → iOS

```swift
// iOS 앱에서 동기화 버튼 탭
await syncService.syncAll()
  ↓
CloudKitService.fetchApps()
CloudKitService.fetchReviews(appID)
  ↓
CoreData (PersistenceController)
  ↓
로컬 저장 완료
```

## ⚙️ CloudKit 스키마

### Record Types

**App:**
- appID (String)
- name (String)
- bundleID (String)
- sku (String)
- iconURL (String, optional)
- lastSynced (Date)

**Review:**
- reviewID (String)
- appID (String) - Reference to App
- rating (Int64)
- title (String, optional)
- body (String, optional)
- reviewerNickname (String, optional)
- createdDate (Date)
- territory (String)
- lastSynced (Date)

**ReviewResponse:**
- responseID (String)
- reviewID (String) - Reference to Review
- responseBody (String)
- lastModifiedDate (Date)
- state (String)

## 🐛 문제 해결

### "Cannot find 'CloudKitService' in scope"
→ `CloudKitService.swift`를 iOS 타겟에 추가

### "Cannot find type 'AppInfo'"
→ `Models.swift`를 iOS 타겟에 추가

### CloudKit 동기화 실패
1. macOS와 iOS가 같은 iCloud Container 사용하는지 확인
2. iCloud 로그인 확인
3. macOS 앱에서 리뷰를 먼저 조회했는지 확인

### CoreData 에러
- 앱 삭제 후 재설치
- Simulator 리셋: `xcrun simctl erase all`

## 📊 테스트 체크리스트

### macOS (기존 기능 유지)
- [ ] API 키 설정
- [ ] 앱 목록 조회
- [ ] 리뷰 조회
- [ ] 리뷰 응답 작성
- [ ] CloudKit 자동 업로드 (콘솔 로그 확인)

### iOS (새로운 앱)
- [ ] 앱 빌드 성공
- [ ] 동기화 버튼 탭
- [ ] CloudKit에서 앱 목록 가져오기
- [ ] CoreData에 저장 확인
- [ ] 앱 목록 표시
- [ ] 리뷰 목록 표시
- [ ] 리뷰 상세 조회
- [ ] 앱 아이콘 표시
- [ ] 검색 기능
- [ ] 오프라인 모드 (비행기 모드에서 데이터 확인)

## 💡 주요 기능

### iOS 앱 화면

1. **앱 탭**
   - 앱 목록 (앱 아이콘 + 이름)
   - 탭하면 리뷰 목록
   - 당겨서 새로고침 (CloudKit 동기화)

2. **리뷰 목록**
   - 별점, 제목, 본문 미리보기
   - 개발자 응답 여부 표시
   - 검색 기능
   - 탭하면 상세 보기

3. **리뷰 상세**
   - 전체 리뷰 내용
   - 개발자 응답 (있는 경우)
   - 읽기 전용 안내

4. **동기화 탭**
   - 마지막 동기화 시간
   - 수동 동기화 버튼
   - 사용 방법 안내

## 🔐 보안 및 개인정보

- API 키는 macOS 앱에만 저장
- iOS 앱은 API 키 불필요
- CloudKit Private Database 사용 (본인만 접근)
- 로컬 CoreData 저장 (기기 외부 유출 없음)

## 🎉 완료!

이제 macOS에서 리뷰를 관리하고, iOS에서 언제든지 확인할 수 있습니다!
