//
//  MessageInputView.swift
//  chess-master-ultimate
//
//  Created by Qiwei Li on 5/17/25.
//

import Agent
import SwiftfulLoadingIndicators
import SwiftUI
import SwiftUIIntrospect

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
    var onSend: () -> Void
    let onCancel: () -> Void
    let status: ChatStatus

    @State private var showModelPicker = false

    init(text: Binding<String>,
         status: ChatStatus,
         currentModel: Binding<Model>,
         currentSource: Binding<Source>,
         sources: [Source],
         onSend: @escaping () -> Void,
         onCancel: @escaping () -> Void = {})
    {
        self._text = text
        self.status = status
        self._currentModel = currentModel
        self.sources = sources
        self.onSend = onSend
        self.onCancel = onCancel
        self._currentSource = currentSource
    }

    var body: some View {
        return VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .textEditorStyle(.plain)
                    .lineSpacing(2)
                    .introspect(.textEditor, on: .macOS(.v11, .v12, .v13, .v14, .v15), customize: { view in
                        view.enclosingScrollView?.scrollerStyle = .overlay
                    })
                    .onKeyPress { press in
                        if press.key == .return && press.modifiers.contains(.shift) {
                            text += "\n"
                            return .handled
                        }
                        return .ignored
                    }
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    }
                    .padding(.top, 10)
            }
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
                        currentModel: $currentModel, currentSource: $currentSource, sources: sources,
                        onClose: { showModelPicker = false }
                    )
                }

                Spacer()
                Button(action: {
                    if status == .loading {
                        onCancel()
                    } else {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
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
                .buttonStyle(.plain)
                .fontWeight(.bold)
                .tint(.black)
                .buttonBorderShape(.circle)
                .background(status == .idle ? .black : .gray.opacity(0.2))
                .cornerRadius(999)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .clipped()
        .frame(maxHeight: 180)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.gray.opacity(0.1))
                .stroke(.gray, lineWidth: 0.2)
        )
        .padding()
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
    @Previewable @State var currentSource: Source = .init(
        displayName: "OpenAI",
        endpoint: "",
        apiKey: "",
        apiType: .openAI,
        models: [
            .openAI(.init(id: "gpt-4o")),
            .openAI(.init(id: "gpt-4")),
        ]
    )

    MessageInputView(
        text: $text,
        status: .idle,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .init(displayName: "OpenAI", endpoint: "", apiKey: "", apiType: .openAI,
                  models: [
                      .openAI(.init(id: "gpt-4o")),
                      .openAI(.init(id: "gpt-4")),
                  ]),
        ],
        onSend: {}
    )
    .frame(height: 300)

    MessageInputView(
        text: $text,
        status: .loading,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .init(displayName: "OpenAI", endpoint: "", apiKey: "", apiType: .openAI,
                  models: [
                      .openAI(.init(id: "gpt-4o")),
                      .openAI(.init(id: "gpt-4")),
                  ]),
        ],
        onSend: {},
        onCancel: {}
    )
    .frame(height: 300)
}
