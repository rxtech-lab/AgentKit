//
//  ThinkingContentView.swift
//  AgentLayout
//
//  Created by Claude on 11/29/25.
//

import Agent
import MarkdownUI
import Shimmer
import Splash
import SwiftUI

/// An expandable view that displays the model's thinking/reasoning process.
/// Shows summary as a clickable title, and expands to show full reasoning content.
struct ThinkingContentView: View {
    /// Summary text shown as the title (from reasoning.summary)
    let summary: String?
    /// Full reasoning content shown when expanded (from reasoningDelta)
    let reasoning: String?
    let status: ChatStatus

    @State private var isExpanded = false

    /// Title text to display (summary or fallback)
    private var titleText: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        }
        return "Thinking..."
    }

    /// Whether there's content to show when expanded
    private var hasExpandableContent: Bool {
        if let reasoning = reasoning, !reasoning.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(), value: isExpanded)
                        .foregroundColor(.gray)

                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.orange.mix(with: .mint, by: 0.9))

                    if status == .loading && summary == nil && (reasoning == nil || reasoning?.isEmpty == true) {
                        Text("Thinking...")
                            .lineLimit(1)
                            .foregroundColor(.orange.mix(with: .mint, by: 0.9))
                            .shimmering()
                    } else {
                        Markdown(titleText)
                            .markdownTheme(.chatTheme)
                            .lineLimit(1)
                            .foregroundColor(.orange.mix(with: .mint, by: 0.9))
                    }
                }
                .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if hasExpandableContent {
                        Markdown(reasoning!)
                            .markdownTheme(.chatTheme)
                            .markdownCodeSyntaxHighlighter(
                                SplashCodeSyntaxHighlighter(
                                    theme: .wwdc18(withFont: .init(size: 14)))
                            )
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No detailed reasoning available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
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

#Preview("With Summary and Reasoning") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ThinkingContentView(
                summary: "The model analyzed the requirements for an ERC20 token implementation...",
                reasoning: """
                Let me think through this step by step:

                1. First, I need to understand the user's question about Solidity programming.
                2. The user wants to implement an ERC20 token, which is a standard interface for fungible tokens.
                3. I should consider the key functions: `transfer`, `approve`, `transferFrom`, `balanceOf`, and `allowance`.
                4. Security considerations are important - we need to prevent overflow/underflow attacks.

                ```solidity
                // SPDX-License-Identifier: MIT
                pragma solidity ^0.8.0;

                contract SimpleToken {
                    mapping(address => uint256) private _balances;
                    uint256 private _totalSupply;
                }
                ```
                """,
                status: .idle
            )
        }
        .padding()
    }
}

#Preview("Summary Only") {
    ThinkingContentView(
        summary: "The model considered multiple approaches before selecting the optimal solution.",
        reasoning: nil,
        status: .idle
    )
    .padding()
}

#Preview("Reasoning Only (No Summary)") {
    ThinkingContentView(
        summary: nil,
        reasoning: "Let me analyze this problem step by step. First, I need to understand the requirements...",
        status: .idle
    )
    .padding()
}

#Preview("Streaming - Loading") {
    ThinkingContentView(
        summary: nil,
        reasoning: nil,
        status: .loading
    )
    .padding()
}

#Preview("Streaming - With Summary") {
    ThinkingContentView(
        summary: "Analyzing the problem...",
        reasoning: "Let me think about this...",
        status: .loading
    )
    .padding()
}
