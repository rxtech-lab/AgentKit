//
//  MessageInputView.swift
//  chess-master-ultimate
//
//  Created by Qiwei Li on 5/17/25.
//

import Agent
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
    let models: [Model]
    var onSend: () -> Void

    @State private var showModelPicker = false

    init(text: Binding<String>,
         currentModel: Binding<Model>,
         models: [Model],
         onSend: @escaping () -> Void)
    {
        self._text = text
        self._currentModel = currentModel
        self.models = models
        self.onSend = onSend
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
                        currentModel: $currentModel, models: models,
                        onClose: { showModelPicker = false })
                }

                Spacer()
                Button(action: {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.white)
                        .font(.system(size: 14))
                        .fontWeight(.black)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .fontWeight(.bold)
                .tint(.black)
                .buttonBorderShape(.circle)
                .background(.black)
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

    MessageInputView(
        text: $text,
        currentModel: $currentModel,
        models: [
            .openAI(.init(id: "gpt-4o")),
            .openAI(.init(id: "gpt-4o-mini")),
            .custom(
                .init(
                    id: "gpt-4o-2024-08-06", endpoint: "https://api.openai.com/v1",
                    apiKey: "sk-proj-1234567890", apiType: .openAI)),
        ],
        onSend: {})
        .frame(height: 800)
}
