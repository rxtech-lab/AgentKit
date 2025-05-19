////
////  ChatListView.swift
////  chess-master-ultimate
////
////  Created by Qiwei Li on 5/17/25.
////
//
//import Agent
//import SwiftUI
//
//#if canImport(UIKit)
//    import UIKit
//#elseif canImport(AppKit)
//    import AppKit
//#endif
//
//struct AgentLayout: View {
////    @State var chat: Chat
////    private let initialChat: Chat
////    @State private var newMessage: String = ""
////    @State private var error: Error? = nil
////    @State private var showAlert: Bool = false
////
////    @Binding var currentModel: Model
////
////    init(chat: Chat, currentModel: Binding<Model>) {
////        self._chat = .init(initialValue: chat)
////        self.initialChat = chat
////        self._currentModel = currentModel
////    }
//
//    var body: some View {
////        VStack(spacing: 0) {
////            ScrollViewReader { proxy in
////                ScrollView {
////                    LazyVStack(spacing: 5) {
////                        ForEach(chat.messages) { message in
////                            ChatMessageRow(
////                                message: message,
////                                onDelete: {
////                                    withAnimation(.easeInOut(duration: 0.3)) {
////                                        chat.messages.removeAll(where: { $0.id == message.id })
////                                    }
////                                },
////                                onEdit: { _, _ in
////                                }
////                            )
////                            .id(message.id)
////                        }
////                    }
////                    .padding(.horizontal)
////                    .padding(.top, 10)
////                    .padding(.bottom, 8)
////                }
////                .onChange(of: chat.messages) { _, _ in
////                    if let lastMessage = chat.messages.last {
////                        withAnimation(.easeInOut(duration: 0.3)) {
////                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
////                        }
////                    }
////                }
////                .onChange(of: chat.messages.count) { _, _ in
////                    if let lastMessage = chat.messages.last {
////                        withAnimation {
////                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
////                        }
////                    }
////                }
////                .onChange(of: initialChat) { _, newVal in
////                    chat = newVal
////                }
////            }
////
////            MessageInputView(text: $newMessage, currentModel: .constant(.openAI(.init(id: "gpt-40"))), models: [],
////                             onSend: {
////                                 Task {
////                                     do {
////                                         let message = newMessage
////                                         newMessage = ""
//        ////                                         try await sendMessage(message: message)
////                                     } catch {
////                                         print("Error sending message: \(error)")
////                                         self.error = error
////                                         self.showAlert = true
////                                     }
////                                 }
////                             })
////        }
////        .alert(
////            "Error to chat", isPresented: $showAlert,
////            actions: {
////                Button("OK", role: .cancel) {
////                    showAlert = false
////                }
////            },
////            message: {
////                if let error = error {
////                    Text(error.localizedDescription)
////                }
////            }
////        )
////        .frame(maxWidth: .infinity)
//
//        return EmptyView()
//    }
//}
