//
//  CodeBlockView.swift
//  ChatGPT-MenuBar
//
//  Created by Qiwei Li on 5/12/23.
//

import MarkdownUI
import SwiftUI

struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration

    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        FontWeight(.regular)
                        ForegroundColor(.text)
                    }
                    .padding(16)
            }
            VStack {
                HStack {
                    Spacer()
                    CopyButton(content: configuration.content)
                        .padding([.top, .trailing], 5.0)
                }
                Spacer()
            }
        }
        .background(Color.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .markdownMargin(top: 0, bottom: 16)
    }
}
