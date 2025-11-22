//
//  ScrollToBottomButton.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/17/25.
//

import SwiftUI

struct ScrollToBottomButton: View {
    let isAtBottom: Bool
    let action: () -> Void

    var body: some View {
        if !isAtBottom {
            if #available(macOS 26.0, *) {
                Button(action: {
                    withAnimation {
                        action()
                    }
                }) {
                    Label("Scroll to bottom", systemImage: "arrow.down")
                }
                .padding()
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: isAtBottom)
            } else {
                Button(action: {
                    withAnimation {
                        action()
                    }
                }) {
                    Label("Scroll to bottom", systemImage: "arrow.down")
                }
                .padding()
                .buttonStyle(.plain)
                .buttonBorderShape(.capsule)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: isAtBottom)
            }
        }
    }
}

#Preview {
    VStack {
        ScrollToBottomButton(isAtBottom: false) {
            print("Scroll to bottom tapped")
        }

        Text("Button hidden when at bottom:")
        ScrollToBottomButton(isAtBottom: true) {
            print("This won't show")
        }
    }
    .padding()
}
