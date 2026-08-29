//
//  ReviewTranslation.swift
//  ReviewManager
//
//  Apple Translation 프레임워크(온디바이스 번역) + 클립보드 복사 공용 컴포넌트
//  macOS 15 / iOS 18 미만에서는 번역 UI가 자동으로 숨겨진다.
//

import SwiftUI
import Translation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 클립보드

enum ReviewClipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// 제목 + 본문을 한 덩어리 텍스트로 합친다
    static func joined(title: String?, body: String?) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        if let body, !body.isEmpty { parts.append(body) }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - 복사 버튼

struct ReviewCopyButton: View {
    let text: String
    var titleKey: LocalizedStringKey = "review.copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            ReviewClipboard.copy(text)
            withAnimation { didCopy = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { didCopy = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                Text(didCopy ? "review.copied" : titleKey)
            }
            .font(.caption)
            .foregroundColor(didCopy ? .green : .accentColor)
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help(Text("review.copy"))
    }
}

// MARK: - 번역 (Apple Translation)

/// 번역 UI 진입점. OS 버전이 낮으면 아무것도 그리지 않는다.
struct ReviewTranslationView: View {
    let reviewTitle: String?
    let reviewBody: String?

    var body: some View {
        if !ReviewClipboard.joined(title: reviewTitle, body: reviewBody).isEmpty {
            if #available(macOS 15.0, iOS 18.0, *) {
                AppleTranslationView(reviewTitle: reviewTitle, reviewBody: reviewBody)
            }
        }
    }
}

@available(macOS 15.0, iOS 18.0, *)
@MainActor
final class ReviewTranslationModel: ObservableObject {
    private static let titleID = "title"
    private static let bodyID = "body"

    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var translatedTitle: String?
    @Published private(set) var translatedBody: String?
    @Published private(set) var isTranslating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isShowingTranslation = false

    private var pendingTitle = ""
    private var pendingBody = ""

    var hasTranslation: Bool { translatedTitle != nil || translatedBody != nil }

    var translatedText: String {
        ReviewClipboard.joined(title: translatedTitle, body: translatedBody)
    }

    /// 번역 보기 / 원문 보기 토글. 아직 번역 결과가 없으면 번역 세션을 시작한다.
    func toggle(title: String?, body: String?) {
        if isShowingTranslation {
            isShowingTranslation = false
            return
        }

        if hasTranslation {
            isShowingTranslation = true
            return
        }

        pendingTitle = title ?? ""
        pendingBody = body ?? ""
        guard !pendingTitle.isEmpty || !pendingBody.isEmpty else { return }

        errorMessage = nil
        isTranslating = true

        // 원문 언어는 시스템이 자동 감지하고, 도착 언어는 기기 설정 언어를 사용한다.
        let target = Locale.current.language
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        } else {
            // 같은 설정으로 세션을 다시 실행시킨다 (재시도)
            configuration?.invalidate()
        }
    }

    /// translationTask 안에서 실제 번역을 수행한다.
    func performTranslation(using session: TranslationSession) async {
        guard isTranslating else { return }
        defer { isTranslating = false }

        var requests: [TranslationSession.Request] = []
        if !pendingTitle.isEmpty {
            requests.append(.init(sourceText: pendingTitle, clientIdentifier: Self.titleID))
        }
        if !pendingBody.isEmpty {
            requests.append(.init(sourceText: pendingBody, clientIdentifier: Self.bodyID))
        }
        guard !requests.isEmpty else { return }

        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                if response.clientIdentifier == Self.titleID {
                    translatedTitle = response.targetText
                } else {
                    translatedBody = response.targetText
                }
            }
            isShowingTranslation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@available(macOS 15.0, iOS 18.0, *)
private struct AppleTranslationView: View {
    let reviewTitle: String?
    let reviewBody: String?

    @StateObject private var model = ReviewTranslationModel()

    private var hasSourceText: Bool {
        !ReviewClipboard.joined(title: reviewTitle, body: reviewBody).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    model.toggle(title: reviewTitle, body: reviewBody)
                } label: {
                    HStack(spacing: 4) {
                        if model.isTranslating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "translate")
                        }
                        Text(translateButtonKey)
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(model.isTranslating || !hasSourceText)

                if model.isShowingTranslation, !model.translatedText.isEmpty {
                    ReviewCopyButton(text: model.translatedText, titleKey: "review.copy.translation")
                }

                Spacer(minLength: 0)
            }

            if model.isShowingTranslation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("review.translation")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let translatedTitle = model.translatedTitle, !translatedTitle.isEmpty {
                        Text(translatedTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)
                    }

                    if let translatedBody = model.translatedBody, !translatedBody.isEmpty {
                        Text(translatedBody)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(8)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .translationTask(model.configuration) { session in
            await model.performTranslation(using: session)
        }
    }

    private var translateButtonKey: LocalizedStringKey {
        if model.isTranslating { return "review.translating" }
        return model.isShowingTranslation ? "review.translate.show_original" : "review.translate"
    }
}
