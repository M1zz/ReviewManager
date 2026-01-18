//
//  ReviewDetailView_iOS.swift
//  ReviewManager (iOS)
//
//  리뷰 상세 화면
//

import SwiftUI

struct ReviewDetailView_iOS: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let review: CustomerReview

    @State private var showingResponseSheet = false
    @State private var showingDeleteAlert = false

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
                    HStack(alignment: .top) {
                        Text(review.starsDisplay)
                            .font(.title2)
                            .foregroundColor(ratingColor)
                            .fixedSize()

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(review.territory)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(6)
                                .fixedSize()

                            Text(review.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }

                    if let title = review.title, !title.isEmpty {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let body = review.body, !body.isEmpty {
                        Text(body)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let nickname = review.reviewerNickname {
                        Text("— \(nickname)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5)

                // 개발자 응답
                if let response = review.response {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundColor(.accentColor)
                                .fixedSize()

                            Text("개발자 응답")
                                .font(.headline)
                                .fixedSize()

                            Spacer(minLength: 8)

                            Text(response.state.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    response.state == .published
                                        ? Color.green.opacity(0.2)
                                        : Color.orange.opacity(0.2)
                                )
                                .cornerRadius(4)
                                .fixedSize()
                        }

                        Text(response.responseBody)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(response.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(12)
                }

                // 액션 버튼
                VStack(spacing: 12) {
                    if review.response != nil {
                        Button {
                            showingResponseSheet = true
                        } label: {
                            Label("응답 수정", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("응답 삭제", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            showingResponseSheet = true
                        } label: {
                            Label("응답하기", systemImage: "arrowshape.turn.up.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("리뷰 상세")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingResponseSheet) {
            ResponseSheet_iOS(review: review)
        }
        .alert("응답 삭제", isPresented: $showingDeleteAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                Task {
                    await appState.deleteResponse(for: review)
                    dismiss()
                }
            }
        } message: {
            Text("이 응답을 삭제하시겠습니까?")
        }
    }
}

// MARK: - Response Sheet
struct ResponseSheet_iOS: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let review: CustomerReview

    @State private var responseText = ""
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 원본 리뷰
                    VStack(alignment: .leading, spacing: 12) {
                        Text("원본 리뷰")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(review.starsDisplay)
                                .fixedSize()

                            if let title = review.title {
                                Text(title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let body = review.body {
                                Text(body)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let nickname = review.reviewerNickname {
                                Text("— \(nickname)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    // 응답 입력
                    VStack(alignment: .leading, spacing: 12) {
                        Text("응답 작성")
                            .font(.headline)

                        TextEditor(text: $responseText)
                            .frame(minHeight: 200)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .focused($isTextEditorFocused)

                        HStack {
                            Text("\(responseText.count) / 5970")
                                .font(.caption)
                                .foregroundColor(responseText.count > 5970 ? .red : .secondary)

                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("리뷰 응답")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("전송") {
                        Task {
                            await appState.respondToReview(review, response: responseText)
                            dismiss()
                        }
                    }
                    .disabled(responseText.isEmpty || responseText.count > 5970 || appState.isLoading)
                }
            }
            .onAppear {
                if let existingResponse = review.response {
                    responseText = existingResponse.responseBody
                }
                isTextEditorFocused = true
            }
        }
    }
}
