import Agent
import SwiftUI

struct ModelPicker: View {
    @Binding var currentModel: Model
    let models: [Model]
    let onClose: () -> Void

    @State private var hoveredModel: Model?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(models) { model in
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
                    if model == currentModel {
                        Spacer()
                        Image(systemName: "checkmark")
                            .padding(.trailing, 12)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        hoveredModel = model
                    } else {
                        hoveredModel = nil
                    }
                }
                .foregroundColor(
                    hoveredModel == model
                        ? .primary : model == currentModel ? .primary : .secondary
                )
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
        .padding()
    }
}

#Preview {
    @Previewable @State var currentModel: Model = .openAI(.init(id: "gpt4o"))
    ModelPicker(currentModel: $currentModel, models: [
        .openAI(.init(id: "gpt4o")),
        .openAI(.init(id: "gpt-4")),
        .openAI(.init(id: "gpt-3.5-turbo")),
        .custom(.init(id: "custom-model", endpoint: "https://example.com", apiKey: "api-key", apiType: .openAI)),
    ]) {}
}
