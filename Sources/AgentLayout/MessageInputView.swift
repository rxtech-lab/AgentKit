//
//  MessageInputView.swift
//  chess-master-ultimate
//
//  Created by Qiwei Li on 5/17/25.
//

import Agent
import SwiftUI
import SwiftUIIntrospect
import SwiftfulLoadingIndicators

// Define placeholder enum if OpenAICompatibleModel is not available at compile time
#if !PREVIEW
    import Foundation
#endif

enum MessageInputState {
    case idle
    case sending
}

struct MessageInputView: View {
    @Binding var text: String
    @Binding var currentModel: Model
    @Binding var currentSource: Source
    let sources: [Source]
    var onSend: (String) -> Void
    let onCancel: () -> Void
    let status: ChatStatus

    @State private var showModelPicker = false

    init(
        text: Binding<String>,
        status: ChatStatus,
        currentModel: Binding<Model>,
        currentSource: Binding<Source>,
        sources: [Source],
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self._text = text
        self.status = status
        self._currentModel = currentModel
        self.sources = sources
        self.onSend = onSend
        self.onCancel = onCancel
        self._currentSource = currentSource
    }

    @ViewBuilder
    private func sendButton() -> some View {
        Button(action: {
            if status == .loading {
                onCancel()
            } else {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSend(text)
                }
            }
        }) {
            if status == .loading {
                Image(systemName: "square.fill")
                    .foregroundStyle(.black)
                    .font(.system(size: 14))
                    .fontWeight(.black)
                    .padding(10)
            } else {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white)
                    .font(.system(size: 14))
                    .fontWeight(.black)
                    .padding(10)
            }
        }
        .disabled(
            status == .idle && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private func inputView() -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .disabled(status == .loading)
                    .lineLimit(1...6)
                    .onKeyPress { press in
                        guard press.key == .return else { return .ignored }
                        if press.modifiers.contains(.shift) {
                            text.append("\n")
                            return .handled
                        }
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend(text)
                        }
                        return .handled
                    }
                    .padding(.vertical)
                    .padding(.horizontal)
            }
            Spacer(minLength: 0)
            HStack {
                Button {
                    showModelPicker.toggle()
                } label: {
                    Text(currentModel.displayName)
                }
                #if os(macOS)
                    .buttonStyle(.accessoryBar)
                #endif
                .popover(isPresented: $showModelPicker) {
                    ModelPicker(
                        currentModel: $currentModel, currentSource: $currentSource,
                        sources: sources,
                        onClose: { showModelPicker = false }
                    )
                }

                Spacer()
                if #available(macOS 26.0, *) {
                    sendButton()
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .fontWeight(.bold)
                        .tint(status == .idle ? .black : .gray.opacity(0.2))
                        .buttonBorderShape(.circle)
                        .cornerRadius(999)
                } else {
                    sendButton()
                        .buttonStyle(.plain)
                        .buttonBorderShape(.circle)
                        .fontWeight(.bold)
                        .tint(.black)
                        .buttonBorderShape(.circle)
                        .background(status == .idle ? .black : .gray.opacity(0.2))
                        .cornerRadius(999)
                }
            }
        }
        .frame(minHeight: 80, maxHeight: 240)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            inputView()
                .glassEffect(in: .rect(cornerRadius: 16.0))
                .padding()
        } else {
            inputView()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.gray, lineWidth: 0.2)
                )
                .padding()
        }
    }
}

#Preview {
    @Previewable @State var text = """
        This is
        very
        very
        very
        very
        very
        very
        very
        very
        very
        very
        very
        very
        long text
        """
    @Previewable @State var currentModel: Model = .openAI(.init(id: "gpt-4o"))
    @Previewable @State var currentSource: Source = .openAI(
        client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
        models: [
            .openAI(.init(id: "gpt-4o")),
            .openAI(.init(id: "gpt-4")),
        ]
    )
    @Previewable @State var shortText = "Hello, world!"

    MessageInputView(
        text: $text,
        status: .idle,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .openAI(
                client: OpenAIClient(
                    apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
                models: [
                    .openAI(.init(id: "gpt-4o")),
                    .openAI(.init(id: "gpt-4")),
                ]
            )
        ],
        onSend: { _ in }
    )
    .frame(height: 250)

    MessageInputView(
        text: $text,
        status: .loading,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .openAI(
                client: OpenAIClient(
                    apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
                models: [
                    .openAI(.init(id: "gpt-4o")),
                    .openAI(.init(id: "gpt-4")),
                ]
            )
        ],
        onSend: { _ in },
        onCancel: {}
    )

    MessageInputView(
        text: $shortText,
        status: .loading,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .openAI(
                client: OpenAIClient(
                    apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
                models: [
                    .openAI(.init(id: "gpt-4o")),
                    .openAI(.init(id: "gpt-4")),
                ]
            )
        ],
        onSend: { _ in },
        onCancel: {}
    )
}
