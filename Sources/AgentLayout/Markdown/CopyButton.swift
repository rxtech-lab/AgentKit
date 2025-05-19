//
//  CopyButton.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import SwiftUI

struct CopyButton: View {
    let content: String
    @State var copied: Bool = false

    var body: some View {
        Button(action: {
            Task {
                await onCopied()
            }
        }, label: {
            if copied {
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "doc.on.doc.fill")
            }
        })
    }

    func onCopied() async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        copied = true
        // Wait 1.5 secs
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation {
            copied = false
        }
    }
}
