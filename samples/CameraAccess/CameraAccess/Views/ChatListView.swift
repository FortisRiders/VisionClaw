import SwiftUI

struct ChatListView: View {
    @ObservedObject var session: JarvisVoiceSession
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var renameTarget: JarvisChat?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var isLoading = false

    private var filtered: [JarvisChat] {
        guard !searchText.isEmpty else { return session.chatList }
        return session.chatList.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.previewText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if isLoading && session.chatList.isEmpty {
                    ProgressView().tint(.white)
                } else if filtered.isEmpty {
                    Text(searchText.isEmpty ? "No conversations yet" : "No results")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.subheadline)
                } else {
                    List {
                        ForEach(filtered) { chat in
                            NavigationLink {
                                ChatDetailView(
                                    chat: chat,
                                    session: session,
                                    dismissSheet: { dismiss() }
                                )
                            } label: {
                                ChatRowContent(chat: chat, isActive: chat.id == session.activeChatId)
                            }
                            .contextMenu {
                                Button {
                                    renameTarget = chat
                                    renameText = chat.title
                                    showRenameAlert = true
                                } label: { Label("Rename", systemImage: "pencil") }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                            .listRowSeparatorTint(.white.opacity(0.1))
                        }
                        .onDelete { indexSet in
                            for i in indexSet { session.deleteChat(filtered[i]) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await session.newChat(); dismiss() }
                    } label: {
                        Image(systemName: "square.and.pencil").foregroundColor(.white)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
        }
        .preferredColorScheme(.dark)
        .task {
            isLoading = true
            await session.loadChatList()
            isLoading = false
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Chat name", text: $renameText)
            Button("Save") {
                if let chat = renameTarget {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { session.renameChat(id: chat.id, title: trimmed) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct ChatDetailView: View {
    let chat: JarvisChat
    @ObservedObject var session: JarvisVoiceSession
    let dismissSheet: () -> Void

    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(.white)
            } else if session.messages.isEmpty {
                Text("No messages yet")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.subheadline)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(session.messages) { message in
                                ChatBubble(message: message)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismissSheet() }
                    .foregroundColor(.white)
            }
        }
        .task {
            await session.switchChat(to: chat)
            isLoading = false
        }
    }
}

private struct ChatRowContent: View {
    let chat: JarvisChat
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? Color(red: 0, green: 0.478, blue: 1.0) : Color.white.opacity(0.2))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !chat.previewText.isEmpty {
                    Text(chat.previewText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(chat.updatedAt.chatTimestamp)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.vertical, 4)
    }
}

private extension Date {
    var chatTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            return DateFormatter.localizedString(from: self, dateStyle: .none, timeStyle: .short)
        }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }
}
