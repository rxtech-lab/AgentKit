import Agent
import SwiftUI

struct ModelPicker: View {
    @Binding var currentModel: Model
    @Binding var currentSource: Source
    let sources: [Source]
    let onClose: () -> Void

    @State private var hoveredModel: Model?
    @State private var searchText: String = ""

    public init(
        currentModel: Binding<Model>,
        currentSource: Binding<Source>,
        sources: [Source],
        onClose: @escaping () -> Void
    ) {
        self._currentModel = currentModel
        self.sources = sources
        self.onClose = onClose
        self._currentSource = currentSource
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(sources) { source in
                        Text(source.displayName)
                            .foregroundColor(Color.gray)

                        ForEach(source.models) { model in
                            HStack {
                                Text(model.displayName)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // if model is custom model, show custom icon
                                if case .custom = model {
                                    Image(systemName: "gear")
                                        .padding()
                                }
                                // if model is custom agent, show agent icon
                                if case .customAgent = model {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .padding()
                                }
                                if model == currentModel {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .padding(.trailing, 12)
                                }
                            }
                            .id(model)
                            .onHover { hovering in
                                if hovering {
                                    hoveredModel = model
                                } else {
                                    hoveredModel = nil
                                }
                            }
                            .background(
                                hoveredModel == model ? Color.gray.opacity(0.12) : Color.clear
                            )
                            .cornerRadius(10)
                            .frame(width: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                withAnimation {
                                    currentModel = model
                                }
                                onClose()
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(currentModel, anchor: .center)
                    }
                }
            }
            .onKeyPress { press in
                if press.key == .escape {
                    searchText = ""
                    return .handled
                }
                if press.key == .delete {
                    if !searchText.isEmpty {
                        searchText.removeLast()
                    }
                    scrollToFirstMatch(proxy: proxy)
                    return .handled
                }
                if let char = press.characters.first, char.isLetter || char.isNumber {
                    searchText.append(char)
                    scrollToFirstMatch(proxy: proxy)
                    return .handled
                }
                return .ignored
            }
        }
    }

    private func scrollToFirstMatch(proxy: ScrollViewProxy) {
        let allModels = sources.flatMap { $0.models }
        if let match = allModels.first(where: {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }) {
            withAnimation {
                proxy.scrollTo(match, anchor: .center)
            }
        }
    }
}

#Preview {
    @Previewable @State var currentModel: Model = .openAI(.init(id: "gpt4o"))
    @Previewable @State var currentSource: Source = .openAI(
        client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
        models: [
            .openAI(.init(id: "gpt-4o")),
            .openAI(.init(id: "gpt-4")),
        ]
    )
    ModelPicker(
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [
            .openAI(
                client: OpenAIClient(
                    apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
                models: [
                    .openAI(.init(id: "gpt-4o")),
                    .openAI(.init(id: "gpt-4")),
                ]),
            .openRouter(
                client: OpenRouterClient(apiKey: ""),
                models: [
                    .openRouter(.init(id: "anthropic/claude-3.5-sonnet")),
                    .openRouter(.init(id: "anthropic/claude-3-opus")),
                ]),
        ]
    ) {}
}
