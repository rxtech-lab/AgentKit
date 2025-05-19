//
//  ToolMessageRow.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Agent
import Shimmer
import SwiftUI

public enum ChatStatus {
    case idle
    case loading
}

struct OpenAIToolMessageRow: View {
    let toolCall: OpenAIToolCall
    let messages: [OpenAIMessage]
    let status: ChatStatus

    @State private var isExpanded = false

    var toolResponse: OpenAIToolMessage? {
        if let message = messages.first(where: { message in
            if case .tool(let toolMessage) = message, toolMessage.toolCallId == toolCall.id {
                return true
            }
            return false
        }), case .tool(let toolMessage) = message {
            return toolMessage
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(), value: isExpanded)

                    if toolResponse != nil {
                        Label {
                            Text("Tool call complete: \(toolCall.function.name)")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .foregroundColor(.orange.mix(with: .mint, by: 0.9))
                    } else if status == .loading {
                        Label {
                            Text("Calling tool: \(toolCall.function.name)")
                                .lineLimit(1)
                                .shimmering()
                        } icon: {
                            Image(systemName: "hourglass.circle.fill")
                                .shimmering()
                        }
                    } else {
                        Label {
                            Text("Calling tool: \(toolCall.function.name)")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "terminal.fill")
                        }
                    }
                }
                .font(.system(size: 14))
                .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Request:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        JSONSyntaxView(jsonString: toolCall.function.arguments)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let toolResponse = toolResponse {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Response:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            JSONSyntaxView(jsonString: toolResponse.content)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if status == .loading {
                        Text("Loading response...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .shimmering()
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading) {
            OpenAIToolMessageRow(
                toolCall: OpenAIToolCall(
                    id: "call_123",
                    type: .function,
                    function: OpenAIToolCall.Function(
                        name: "get_weather", arguments: "{\"location\": \"New York\"}"
                    )
                ),
                messages: [
                    .tool(
                        OpenAIToolMessage(
                            content: "{\"temperature\": 72, \"condition\": \"sunny\"}",
                            toolCallId: "call_123"
                        ))
                ],
                status: .idle
            )

            OpenAIToolMessageRow(
                toolCall: OpenAIToolCall(
                    id: "call_123",
                    type: .function,
                    function: OpenAIToolCall.Function(
                        name: "get_weather", arguments: "{\"location\": \"New York\"}"
                    )
                ),
                messages: [
                    .tool(
                        OpenAIToolMessage(
                            content: "{\"temperature\": 72, \"condition\": \"sunny\"}",
                            toolCallId: "call_123"
                        ))
                ],
                status: .loading
            )

            OpenAIToolMessageRow(
                toolCall: OpenAIToolCall(
                    id: "call_456",
                    type: .function,
                    function: OpenAIToolCall.Function(
                        name: "search_web", arguments: "{\"query\": \"Swift programming language\"}"
                    )
                ),
                messages: [],
                status: .loading
            )
        }
        .padding()
    }
}

#Preview("JSON Syntax View") {
    VStack(spacing: 16) {
        JSONSyntaxView(
            jsonString:
            "{\"name\": \"John\", \"age\": 30, \"isAdmin\": true, \"roles\": [\"user\", \"editor\"], \"settings\": null}"
        )
        .frame(height: 200)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        JSONSyntaxView(jsonString: "{\"invalid json")
            .frame(height: 50)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
    }
    .padding()
}
