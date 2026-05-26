/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI
import UIKit

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @ObservedObject private var profileManager = ProfileManager.shared
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @StateObject private var webrtcVM = WebRTCSessionViewModel()
  @StateObject private var jarvisSession = JarvisVoiceSession()
  @State private var showJarvisPanel = false
  @State private var showSwitchProfile = false

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM, webrtcVM: webrtcVM, jarvisSession: jarvisSession, showJarvisPanel: $showJarvisPanel, onProfileTap: { showSwitchProfile = true })
      } else {
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, showJarvisPanel: $showJarvisPanel, onProfileTap: { showSwitchProfile = true })
      }

      if showJarvisPanel {
        JarvisPTTView(
          session: jarvisSession,
          audioManager: geminiVM.isGeminiActive ? geminiVM.audioManager : nil,
          onDismiss: { withAnimation(.easeInOut(duration: 0.3)) { showJarvisPanel = false } }
        )
        .transition(.move(edge: .trailing))
      }
    }
    .gesture(
      DragGesture(minimumDistance: 60)
        .onEnded { value in
          let horizontal = value.translation.width
          let vertical = abs(value.translation.height)
          guard vertical < abs(horizontal) else { return }
          withAnimation(.easeInOut(duration: 0.3)) {
            if horizontal < -60 { showJarvisPanel = true }
            else if horizontal > 60 { showJarvisPanel = false }
          }
        }
    )
    .task {
      viewModel.geminiSessionVM = geminiVM
      viewModel.webrtcSessionVM = webrtcVM
      viewModel.jarvisSessionVM = jarvisSession
      geminiVM.streamingMode = viewModel.streamingMode
      LocationManager.shared.requestPermissionAndStart()
      let session: JarvisVoiceSession = jarvisSession
      let vm: StreamSessionViewModel = viewModel
      session.frameProvider = { [weak vm] in vm?.recentFrames() ?? [] }
      NotificationManager.shared.onStopRequested = { [weak session, weak vm] in
        session?.stopLiveMode()
        Task { await vm?.stopSession() }
      }
      session.onStopSessionRequested = { [weak session, weak vm] in
        session?.stopLiveMode()
        Task { await vm?.stopSession() }
      }
      AppSessionCoordinator.shared.register(jarvis: jarvisSession, gemini: geminiVM)
    }
    .onChange(of: profileManager.activeProfile?.id) {
      AppSessionCoordinator.shared.profileDidSwitch()
    }
    .onChange(of: webrtcVM.isActive) { newValue in
      jarvisSession.isLiveStreamingActive = newValue
      if jarvisSession.isLiveModeActive {
        jarvisSession.updateLiveActivityForStreamingChange()
      }
    }
    .onChange(of: viewModel.streamingMode) { newMode in
      geminiVM.streamingMode = newMode
    }
    .onAppear {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear {
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .sheet(isPresented: $showSwitchProfile) {
      ProfileDetailSheet(jarvisSession: jarvisSession)
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
