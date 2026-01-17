# Review Manager

App Store 리뷰를 편리하게 관리하는 macOS 앱입니다.

## 주요 기능

- 📱 **앱 목록 조회**: 내가 소유한 모든 앱을 한눈에 확인
- ⭐ **리뷰 관리**: 고객 리뷰를 편리하게 조회하고 필터링
- 💬 **빠른 응답**: 리뷰에 바로 응답 작성, 수정, 삭제
- 📊 **통계 확인**: 평균 평점, 총 리뷰 수, 응답률 확인
- 🔍 **검색 및 필터**: 별점별, 응답 상태별 필터링 및 검색

## 시스템 요구사항

- macOS 14.0 (Sonoma) 이상
- Xcode 15.0 이상

## 설치 방법

1. `ReviewManager.xcodeproj`를 Xcode로 엽니다
2. 필요시 Team과 Bundle Identifier를 수정합니다
3. Build & Run (⌘R)

## App Store Connect API 설정

앱을 사용하려면 App Store Connect API 키가 필요합니다.

### API 키 생성 방법

1. [App Store Connect](https://appstoreconnect.apple.com)에 로그인
2. **사용자 및 액세스** 클릭
3. 상단 **통합** 탭 선택
4. **App Store Connect API** 페이지에서:
   - **Issuer ID**: 페이지 상단에 표시됨
   - **팀 키** 탭에서 **+** 또는 **API 키 생성** 클릭
5. 키 이름 입력 및 **관리(Admin)** 권한 선택
6. **생성** 클릭
7. 생성된 키 정보 저장:
   - **Key ID**: 키 목록에서 확인
   - **Private Key (.p8)**: 다운로드 (⚠️ 한 번만 다운로드 가능!)

### 앱에서 연결하기

1. 앱을 실행하면 온보딩 화면이 표시됩니다
2. 안내에 따라 Issuer ID, Key ID, Private Key를 입력합니다
3. "연결하기" 버튼을 클릭하면 API 연결이 완료됩니다

## 프로젝트 구조

```
ReviewManager/
├── ReviewManagerApp.swift      # 앱 진입점 및 AppState
├── Models/
│   └── Models.swift            # 데이터 모델
├── Views/
│   ├── ContentView.swift       # 메인 화면
│   ├── OnboardingView.swift    # 온보딩/설정 화면
│   └── SettingsView.swift      # 설정 화면
├── Services/
│   └── AppStoreConnectService.swift  # API 통신 서비스
└── Assets.xcassets/            # 앱 아이콘 및 색상
```

## 주요 API 엔드포인트

- `GET /v1/apps` - 앱 목록 조회
- `GET /v1/apps/{id}/customerReviews` - 리뷰 목록 조회
- `POST /v1/customerReviewResponses` - 리뷰 응답 작성
- `DELETE /v1/customerReviewResponses/{id}` - 리뷰 응답 삭제

## 보안

- API 인증 정보는 로컬 UserDefaults에만 저장됩니다
- Private Key는 외부로 전송되지 않습니다
- App Sandbox 및 Hardened Runtime이 적용되어 있습니다

## 커스터마이징

### Bundle Identifier 변경

`ReviewManager.xcodeproj`에서 타겟 설정의 **Signing & Capabilities**에서 수정

### 앱 아이콘 추가

`Assets.xcassets/AppIcon.appiconset/`에 아이콘 이미지 추가

## 라이선스

MIT License

## 참고 문서

- [App Store Connect API Documentation](https://developer.apple.com/documentation/appstoreconnectapi)
- [Customer Reviews API](https://developer.apple.com/documentation/appstoreconnectapi/customer-reviews)
- [Customer Review Responses API](https://developer.apple.com/documentation/appstoreconnectapi/customer-review-responses)
