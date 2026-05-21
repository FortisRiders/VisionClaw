/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import CoreImage
import CoreMedia
import CoreVideo
import MWDATCamera
import MWDATCore
import SwiftUI
import VideoToolbox

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum StreamingMode {
  case glasses
  case iPhone
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false
  @Published var streamingMode: StreamingMode = .glasses
  @Published var selectedResolution: StreamingResolution = .low

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  var resolutionLabel: String {
    switch selectedResolution {
    case .low: return "360x640"
    case .medium: return "504x896"
    case .high: return "720x1280"
    @unknown default: return "Unknown"
    }
  }

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  // Gemini Live integration
  var geminiSessionVM: GeminiSessionViewModel?

  // WebRTC Live streaming integration
  var webrtcSessionVM: WebRTCSessionViewModel?

  // Jarvis voice session — used to report live-mode state in background notifications
  weak var jarvisSessionVM: JarvisVoiceSession?

  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?
  private var iPhoneCameraManager: IPhoneCameraManager?

  // CPU-based CIContext for rendering decoded pixel buffers in background
  private let cpuCIContext = CIContext(options: [.useSoftwareRenderer: true])
  // VideoDecoder for decompressing HEVC/H.264 frames in background
  private let videoDecoder = VideoDecoder()
  private var backgroundFrameCount = 0

  // Rolling 15-second frame buffer at 1fps for Jarvis vision queries
  private var jarvisFrameBuffer: [UIImage] = []
  private var lastBufferedFrameTime: Date = .distantPast
  private let maxBufferFrames = 15
  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    setupVideoDecoder()
    attachListeners()
    observeAppTermination()
  }

  private func observeAppTermination() {
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else {
        NSLog("[Notify] didEnterBackground — self is nil, skipping")
        return
      }
      NSLog("[Notify] didEnterBackground — streamingStatus=%@ jarvisLive=%@",
            String(describing: self.streamingStatus),
            self.jarvisSessionVM?.isLiveModeActive == true ? "YES" : "NO")
      guard self.streamingStatus != .stopped else {
        NSLog("[Notify] didEnterBackground — not streaming, skipping notification")
        return
      }
      let jarvisLive = self.jarvisSessionVM?.isLiveModeActive ?? false
      NotificationManager.shared.sendSessionActiveInBackground(jarvisLive: jarvisLive)
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      NSLog("[Notify] willTerminate — streamingStatus=%@",
            String(describing: self?.streamingStatus))
      guard let self, self.streamingStatus != .stopped else { return }
      NotificationManager.shared.sendStreamEnded()
    }
  }

  private func setupVideoDecoder() {
    videoDecoder.setFrameCallback { [weak self] decodedFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let pixelBuffer = decodedFrame.pixelBuffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = self.cpuCIContext.createCGImage(ciImage, from: rect) {
          let image = UIImage(cgImage: cgImage)
          let toGemini = self.geminiSessionVM?.isGeminiActive == true
          let toWebRTC = self.webrtcSessionVM?.isActive == true
          if toGemini { self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image) }
          if toWebRTC { self.webrtcSessionVM?.pushVideoFrame(image) }
          self.bufferFrameIfNeeded(image)
          if self.backgroundFrameCount <= 5 || self.backgroundFrameCount % 120 == 0 {
            NSLog("[FrameRoute] BG frame #%d → Gemini:%@ WebRTC:%@ JarvisBuffer:%d (%dx%d)",
                  self.backgroundFrameCount,
                  toGemini ? "YES" : "no", toWebRTC ? "YES" : "no",
                  self.jarvisFrameBuffer.count, width, height)
          }
        }
      }
    }
  }

  /// Recreate the StreamSession with the current selectedResolution.
  /// Only call when not actively streaming.
  func updateResolution(_ resolution: StreamingResolution) {
    guard !isStreaming else { return }
    selectedResolution = resolution
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: resolution,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
    attachListeners()
    NSLog("[Stream] Resolution changed to %@", resolutionLabel)
  }

  private func attachListeners() {
    // Subscribe to session state changes using the DAT SDK listener pattern
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        NSLog("[Stream] State → %@", String(describing: state))
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // This callback fires whether the app is in the foreground or background,
    // enabling continuous streaming even when the screen is locked.
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        let isInBackground = UIApplication.shared.applicationState == .background

        if !isInBackground {
          self.backgroundFrameCount = 0
          if let image = videoFrame.makeUIImage() {
            self.currentVideoFrame = image
            if !self.hasReceivedFirstFrame {
              self.hasReceivedFirstFrame = true
              NSLog("[FrameRoute] First glasses frame received")
            }
            let toGemini = self.geminiSessionVM?.isGeminiActive == true
            let toWebRTC = self.webrtcSessionVM?.isActive == true
            if toGemini { self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image) }
            if toWebRTC { self.webrtcSessionVM?.pushVideoFrame(image) }
            self.bufferFrameIfNeeded(image)
            if toGemini || toWebRTC {
              NSLog("[FrameRoute] FG frame → Gemini:%@ WebRTC:%@ JarvisBuffer:%d",
                    toGemini ? "YES" : "no", toWebRTC ? "YES" : "no", self.jarvisFrameBuffer.count)
            }
          }
        } else {
          // In background: makeUIImage() uses VideoToolbox GPU rendering which iOS suspends.
          // Instead, use our VideoDecoder (VTDecompressionSession) to decode compressed
          // frames into pixel buffers, then convert via CPU CIContext.
          self.backgroundFrameCount += 1

          let sampleBuffer = videoFrame.sampleBuffer
          let hasCompressedData = CMSampleBufferGetDataBuffer(sampleBuffer) != nil

          if hasCompressedData {
            // Compressed frame (HEVC/H.264) - decode via VTDecompressionSession
            do {
              try self.videoDecoder.decode(sampleBuffer)
            } catch {
              if self.backgroundFrameCount <= 5 || self.backgroundFrameCount % 120 == 0 {
                NSLog("[Stream] Background frame #%d decode error: %@",
                      self.backgroundFrameCount, String(describing: error))
              }
            }
          } else if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            // Raw pixel buffer - convert directly via CPU CIContext
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if let cgImage = self.cpuCIContext.createCGImage(ciImage, from: rect) {
              let image = UIImage(cgImage: cgImage)
              let toGemini = self.geminiSessionVM?.isGeminiActive == true
              let toWebRTC = self.webrtcSessionVM?.isActive == true
              if toGemini { self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image) }
              if toWebRTC { self.webrtcSessionVM?.pushVideoFrame(image) }
              NSLog("[FrameRoute] BG raw pixel → Gemini:%@ WebRTC:%@ (%dx%d)",
                    toGemini ? "YES" : "no", toWebRTC ? "YES" : "no", width, height)
            }
            self.videoDecoder.invalidateSession()
          }
        }
      }
    }

    // Subscribe to streaming errors
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        NSLog("[Stream] SDK error: %@", String(describing: error))
        // Suppress device-not-found errors when user hasn't started streaming yet
        if self.streamingStatus == .stopped {
          if case .deviceNotConnected = error { return }
          if case .deviceNotFound = error { return }
        }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
  }

  func handleStartStreaming() async {
    NotificationManager.shared.requestPermission()
    let permission = Permission.camera
    NSLog("[Stream] Checking camera permission, hasActiveDevice=%@", hasActiveDevice ? "true" : "false")
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      NSLog("[Stream] Permission status: %@", String(describing: status))
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      NSLog("[Stream] Permission request result: %@", String(describing: requestStatus))
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      NSLog("[Stream] Permission check error: %@", error.description)
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    NSLog("[Stream] Calling streamSession.start(), current state: %@", String(describing: streamSession.state))
    await streamSession.start()
    NSLog("[Stream] streamSession.start() returned, state now: %@", String(describing: streamSession.state))
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    if streamingMode == .iPhone {
      stopIPhoneSession()
      return
    }
    await streamSession.stop()
  }

  // MARK: - iPhone Camera Mode

  func handleStartIPhone() async {
    let granted = await IPhoneCameraManager.requestPermission()
    if granted {
      startIPhoneSession()
    } else {
      showError("Camera permission denied. Please grant access in Settings.")
    }
  }

  private func startIPhoneSession() {
    streamingMode = .iPhone
    let camera = IPhoneCameraManager()
    camera.onFrameCaptured = { [weak self] image in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.currentVideoFrame = image
        if !self.hasReceivedFirstFrame {
          self.hasReceivedFirstFrame = true
        }
        self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
        self.webrtcSessionVM?.pushVideoFrame(image)
        self.bufferFrameIfNeeded(image)
      }
    }
    camera.start()
    iPhoneCameraManager = camera
    streamingStatus = .streaming
    NSLog("[Stream] iPhone camera mode started")
  }

  private func stopIPhoneSession() {
    iPhoneCameraManager?.stop()
    iPhoneCameraManager = nil
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    streamingStatus = .stopped
    streamingMode = .glasses
    jarvisFrameBuffer = []
    NSLog("[Stream] iPhone camera mode stopped")
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func capturePhoto() {
    streamSession.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  // Returns up to `count` frames sampled evenly from the rolling buffer.
  // Returns empty array if streaming hasn't started or buffer is empty.
  func recentFrames(count: Int = 4) -> [UIImage] {
    guard !jarvisFrameBuffer.isEmpty else { return [] }
    let buf = jarvisFrameBuffer
    guard buf.count > count else { return buf }
    let step = Double(buf.count) / Double(count)
    return (0..<count).map { buf[Int(Double($0) * step)] }
  }

  private func bufferFrameIfNeeded(_ image: UIImage) {
    let now = Date()
    guard now.timeIntervalSince(lastBufferedFrameTime) >= 1.0 else { return }
    lastBufferedFrameTime = now
    jarvisFrameBuffer.append(image)
    if jarvisFrameBuffer.count > maxBufferFrames {
      jarvisFrameBuffer.removeFirst()
    }
    NSLog("[FrameRoute] Jarvis buffer updated: %d/%d frames", jarvisFrameBuffer.count, maxBufferFrames)
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    switch state {
    case .stopped:
      let wasActive = streamingStatus != .stopped
      currentVideoFrame = nil
      streamingStatus = .stopped
      jarvisFrameBuffer = []
      if wasActive && UIApplication.shared.applicationState != .active {
        NotificationManager.shared.sendStreamEnded()
      }
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    case .hingesClosed:
      return "The hinges on the glasses were closed. Please open the hinges and try again."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
