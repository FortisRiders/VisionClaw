import Speech
import SwiftUI

struct JarvisPTTView: View {
    @ObservedObject var session: JarvisVoiceSession
    let audioManager: AudioManager?
    let onDismiss: () -> Void

    @State private var isPressingButton = false
    @State private var isPulsing = false
    @State private var permissionsGranted = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isTextMode = false
    @State private var textInput = ""
    @State private var showClearConfirmation = false
    @State private var showChatList = false
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                header
                chatArea.frame(maxHeight: .infinity)
                transcriptArea
                Spacer().frame(height: 16)
                bottomBar
                    .padding(.bottom, 32)
            }
        }
        .task {
            permissionsGranted = await session.requestPermissions()
        }
        .sheet(isPresented: $showChatList) {
            ChatListView(session: session)
        }
        .alert("Jarvis", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onChange(of: session.state) { newState in
            isPulsing = newState == .listening
        }
        .onChange(of: session.messages.count) { _ in
            scrollToBottom()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            CustomButton(title: "", icon: "xmark", style: .ghost, isDisabled: false) {
                session.cancel(sharedAudioManager: audioManager)
                onDismiss()
            }
            Spacer()
            Text(session.activeChatTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Button(action: { showChatList = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Chat

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if session.messages.isEmpty {
                        Text("Press and hold to talk to Jarvis")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 48)
                    } else {
                        ForEach(session.messages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptArea: some View {
        if session.state == .sending {
            HStack(spacing: 8) {
                ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.8)
                Text("Thinking...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.vertical, 14)
        } else if !session.liveTranscript.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(session.liveTranscript)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 14)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    // MARK: - Bottom bar (voice or text)

    @ViewBuilder
    private var bottomBar: some View {
        if isTextMode {
            textInputBar
        } else {
            voiceBar
        }
    }

    private var voiceBar: some View {
        ZStack(alignment: .bottomTrailing) {
            pttButton
                .frame(maxWidth: .infinity)

            CustomButton(title: "", icon: "keyboard", style: .ghost, isDisabled: false) {
                isTextMode = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    textFieldFocused = true
                }
            }
            .padding(.trailing, 24)
            .padding(.bottom, 8)
        }
    }

    private var textInputBar: some View {
        HStack(spacing: 10) {
            CustomButton(title: "", icon: "mic.fill", style: .ghost, isDisabled: false) {
                isTextMode = false
                textFieldFocused = false
            }

            TextField("Message Jarvis…", text: $textInput)
                .focused($textFieldFocused)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .submitLabel(.send)
                .onSubmit { submitText() }

            Button(action: { submitText() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(textInput.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.3)
                        : Color(red: 0, green: 0.478, blue: 1.0))
            }
            .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty || session.state != .idle)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - PTT button

    private var pttButton: some View {
        let isDisabled = session.state == .sending || session.state == .speaking || !permissionsGranted

        return ZStack {
            if isPulsing {
                Circle()
                    .fill(buttonColor.opacity(0.25))
                    .frame(width: 152, height: 152)
                    .scaleEffect(isPulsing ? 1.0 : 0.85)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            }

            Circle()
                .fill(buttonColor)
                .frame(width: 120, height: 120)
                .shadow(color: buttonColor.opacity(0.4), radius: isPulsing ? 16 : 6)

            if session.state == .sending {
                ProgressView().tint(.white).scaleEffect(1.4)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                    if let label = buttonLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
        .frame(width: 152, height: 152)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDisabled, !isPressingButton, session.state == .idle else { return }
                    isPressingButton = true
                    session.startListening(sharedAudioManager: audioManager)
                }
                .onEnded { _ in
                    guard isPressingButton else { return }
                    isPressingButton = false
                    if session.state == .listening {
                        session.stopListeningAndSend(sharedAudioManager: audioManager)
                    }
                }
        )
        .opacity(isDisabled ? 0.5 : 1.0)
    }

    // MARK: - Helpers

    private func submitText() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textInput = ""
        session.sendText(trimmed)
    }

    private func scrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy?.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var buttonColor: Color {
        switch session.state {
        case .idle:      return Color.white.opacity(0.18)
        case .listening: return Color.red
        case .sending:   return Color.gray.opacity(0.45)
        case .speaking:  return Color(red: 0.2, green: 0.45, blue: 0.95)
        }
    }

    private var buttonIcon: String {
        switch session.state {
        case .idle:      return "mic.fill"
        case .listening: return "waveform"
        case .sending:   return "ellipsis"
        case .speaking:  return "speaker.wave.3.fill"
        }
    }

    private var buttonLabel: String? {
        switch session.state {
        case .idle:      return "Hold to Talk"
        case .listening: return "Listening..."
        case .sending:   return nil
        case .speaking:  return "Speaking"
        }
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    private var bubbleColor: Color {
        isUser ? Color(red: 0, green: 0.478, blue: 1.0) : Color(white: 0.2)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Circle()
                    .fill(Color(white: 0.25))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text("J")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    )
            }

            Text(message.text)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
