//
//  CameraController.swift
//  InStyler
//
//  Created by Denis Dzyuba on 29/11/20.
//

import UIKit
@preconcurrency import AVFoundation
import Photos
import CoreML
import Vision
import VisionKit
import SwiftUI
import Accelerate

struct FancyImage: @unchecked Sendable {
    var ui: UIImage?
    var buf: CVPixelBuffer?
}

protocol CameraControllerUIDelegate {
    func inErrorState(_: Bool)
}

class CameraController: NSObject, @unchecked Sendable {
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var audioDevice: AVCaptureDevice?
    var audioInput:  AVCaptureDeviceInput?
    var cameraOutput: AVCaptureVideoDataOutput?
    var mikeOutput: AVCaptureAudioDataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var shakeCountDown: Timer?
    var recorded: Int64 = 0
    var timeScale: Int64 = 60
    var secondsToReachGoal = 30
    
    var videoWriter: AVAssetWriter?
    var isRecording: Bool = false
    var videoWriterInput: AVAssetWriterInput?
    var audioWriterInput: AVAssetWriterInput?
    
    var frames: Int64 = 0
    var isPortrait: Bool = true
    var frameWidth = 1080
    var frameHeight = 1920
    
    var recordingStartTime: Double = 0
    
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    var outputFileLocation: URL?
    
    var useFront = false
    
    nonisolated(unsafe) private static var _instance: CameraController? = nil
    private var prepareQueue = DispatchQueue(label: "prepare")              // A serial queue on which we'll receive and process the frames
    private var assetWriteQueue = DispatchQueue(label: "assetWriterQueue")  // A serial queue on which we'll wait for the writer's availability and prepare the pixel buffer for each frame

    // CI context for rendering
    private let ciContext = CIContext(options: nil)

    // Queued video sample carrying stylized buffer and timing
    private struct QueuedVideoSample {
        let pixelBuffer: CVPixelBuffer
        let sampleBuffer: CMSampleBuffer
        let previewImage: UIImage?
    }
    
    // Bounded queues to decouple capture from encoding
    private var videoQueue: [QueuedVideoSample] = []
    private var audioQueue: [CMSampleBuffer] = []
    private let videoQueueMaxCount = 90 // ~3 seconds at 30 fps
    private let audioQueueMaxCount = 256

    // Encoding control
    private var encodingTimer: DispatchSourceTimer?
    private var encodingActive = false

    // Writer session start control
    private var didStartSession = false
    private var sessionStartPTS: CMTime = .invalid

    // Timing
    private var basePTS: CMTime = .zero
    private var frameIndex: Int64 = 0
    private var nominalFrameDuration: CMTime = CMTime(value: 1, timescale: 30)
    
    var didOutputNewImage: (UIImage) -> Void = {_ in }
    
    var uiDelegate: CameraControllerUIDelegate? = nil
    
    private var writerLock = NSLock() // For extra insurance that only one sample buffer will be processed at a time
    private var erroredOut = false
    
    var chachedBuffer: CVPixelBuffer? = nil
    
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    @AppStorage("chosenStyle") var chosenStyle: Int?
    var showError: Bool { didSet{uiDelegate?.inErrorState(showError)}}
    var destinationURL: URL {
        get {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            return URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mp4")
        }
    }
    
    var destinationFileExists: Bool {
        get {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mp4")
            return FileManager.default.fileExists(atPath: videoOutputUrl.path)
        }
    }
    
    private override init() {
        showError = false
        super.init()
    }
    
    public static var instance: CameraController {
        if _instance == nil {
            _instance = CameraController()
        }
        return _instance!
    }
    
    //MARK: - Stylising function
    private func stylizeFrame(_ imageBuffer: CVPixelBuffer) -> FancyImage {
        let originalSize = CVImageBufferGetEncodedSize(imageBuffer)
        
        if (frameWidth != Int(originalSize.width)) {
            frameWidth = Int(originalSize.width)
        }
        
        if (frameHeight != Int(originalSize.height)) {
            frameHeight = Int(originalSize.height)
        }
        
        if let buf = stylizePicture(imageBuffer, chosenStyle: chosenStyle, forImages: false) {
            let ciFinal = CIImage(cvPixelBuffer: buf).transformed(by: .init(scaleX: originalSize.width / dims, y: originalSize.height / dims))
            
            let ui = UIImage(ciImage: ciFinal)
            
            return FancyImage(ui: ui, buf: ui.toBuffer())
        }
        else {
            return FancyImage(ui: nil, buf: nil)
        }
        
    }
    
    private func videoOrientation() -> (CGFloat?, Bool) {
        guard self.frontCamera != nil else { return (nil, false) }
        
        let rc = AVCaptureDevice.RotationCoordinator(device: self.frontCamera!, previewLayer: nil)
        return (rc.videoRotationAngleForHorizonLevelCapture, rc.device?.isPortraitEffectActive ?? false)
    }

    //MARK: - Prepare method
    @Sendable func prepare(completionHandler: @Sendable @escaping (Error?) -> Void){
        erroredOut = false
        //MARK: - Create capture session
        @Sendable func createCaptureSession(){
            self.captureSession = AVCaptureSession()
        }
        
        //MARK: - Configure capture devices
        @Sendable func configureCaptureDevices() throws {
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: useFront ? .front : .back)
            self.frontCamera = camera
            
            let audioDevice = AVCaptureDevice.default(for: .audio)
            self.audioDevice = audioDevice
        }
        
        //MARK: - Configure device input
        @Sendable func configureDeviceInputs() throws {
            guard let captureSession = captureSession else { throw CameraControllerError.captureSessionIsMissing }
            
            if let frontCamera = frontCamera {
                frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                
                if captureSession.canAddInput(frontCameraInput!) {
                    captureSession.addInput(frontCameraInput!)
                }
                else {
                    throw CameraControllerError.inputsAreInvalid
                }
                
            }
            else { throw CameraControllerError.noCamerasAvailable }
            
            try configureAudioInputs()
        }
        
        //MARK: - Configure audio input
        @Sendable func configureAudioInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
            
            guard let audioDevice = self.audioDevice else { return }
            
            audioInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if (audioInput != nil){
                if captureSession.canAddInput(audioInput!){
                    #if DEBUG
                    print("audio input added to capture")
                    #endif
                    captureSession.addInput(audioInput!)
                }
                else {
                    throw CameraControllerError.inputsAreInvalid
                }
            }
        }
        
        prepareQueue.async {[unowned self] in
            do {
                if self.captureSession != nil {
                    self.captureSession!.stopRunning()
                    self.captureSession = nil
                }
                
                createCaptureSession()
                
                self.captureSession!.beginConfiguration()
                
                try configureCaptureDevices()
                try configureDeviceInputs()
                
                self.cameraOutput = AVCaptureVideoDataOutput()
                self.cameraOutput!.alwaysDiscardsLateVideoFrames = false // To avoid dropping frames we want to buffer
                self.cameraOutput!.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
                
                self.mikeOutput = AVCaptureAudioDataOutput()
                self.mikeOutput!.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
                
                if (self.captureSession != nil)
                {
                    // always make sure the AVCaptureSession can accept the selected output
                    if self.captureSession!.canAddOutput(self.cameraOutput!) {
                        // add the output to the current session
                        self.captureSession!.addOutput(self.cameraOutput!)
                        let connection = self.cameraOutput!.connection(with: .video)
                        
                        if connection != nil {
                            let rotation: (CGFloat?, Bool) = self.videoOrientation()
                            if let angle = rotation.0, connection!.isVideoRotationAngleSupported(angle) {
                                connection!.videoRotationAngle = angle
                                self.isPortrait = rotation.1
                            }
                        }
                        else {
                            self.isPortrait = true
                        }

                    }
                    
                    if self.captureSession!.canAddOutput(self.mikeOutput!){
                        #if DEBUG
                        print("audio output added")
                        #endif
                        self.captureSession!.addOutput(self.mikeOutput!)
                    }
                }
                
                self.captureSession!.commitConfiguration()
                self.captureSession!.startRunning()
            }
            catch {
                Task{@MainActor in
                    completionHandler(error)
                }
                
                return
            }
            
            Task {@MainActor in
                completionHandler(nil)
            }
        }
    }
    
    @MainActor func unprepare() {
        erroredOut = false
        prepareQueue.async {[unowned self] in
            if self.captureSession != nil {
                self.captureSession!.stopRunning()
                self.captureSession = nil
            }
        }
    }
    
    @MainActor func startRecording() {
        erroredOut = false
        _ = videoFileLocation() // To get rid of whatever may already be in the destination folder
        prepareQueue.asyncAndWait {[unowned self] in
            guard !isRecording else { return }
            
            if !self.captureSession!.isRunning {
                self.captureSession!.startRunning()
            }
            
            frames = 0
            
            isRecording = true
            
            setUpWriter()
            startEncodingLoop()
        }
        #if DEBUG
        print(isRecording)
        print(videoWriter ?? "the video writer is NULL")
        if videoWriter?.status == .writing {
            print("status writing")
        } else if videoWriter?.status == .failed {
            print("status failed")
        } else if videoWriter?.status == .cancelled {
            print("status cancelled")
        } else if videoWriter?.status == .unknown {
            print("status unknown")
        } else {
            print("status completed")
        }
        #endif
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        prepareQueue.asyncAndWait {[unowned self] in
            
            // Stop the loop and drain remaining queued samples synchronously
            stopEncodingLoop()
            assetWriteQueue.sync { [unowned self] in
                // Drain any remaining items
                while !(videoQueue.isEmpty) || !(audioQueue.isEmpty) {
                    drainQueues()
                    // If inputs are not ready, break to avoid infinite loops
                    if !(videoWriterInput?.isReadyForMoreMediaData ?? false) && !(audioWriterInput?.isReadyForMoreMediaData ?? false) {
                        break
                    }
                }
            }

            audioWriterInput?.markAsFinished()
            videoWriterInput?.markAsFinished()

            // Clear any leftover items
            videoQueue.removeAll()
            audioQueue.removeAll()
            
            @Sendable func processErroringOut(){
                Task {@MainActor [weak self] in
                    if !(self?.showError ?? false) && !(self?.erroredOut ?? false) {
                        self?.erroredOut = false
                        self?.showError = true
                    }
                }
            }
            
            if (videoWriter != nil) {
                videoWriter!.finishWriting { [weak self] in
                    guard self != nil else {
                        return
                    }
                    
#if DEBUG
                    func pringVideoWriterStatus() {
                        print("cancelling writing")
                        let status = switch self!.videoWriter!.status {
                        case .completed: "status: completed"
                        case .writing: "status: writing"
                        case .cancelled: "status: cancelled"
                        case .failed: "status: failed"
                        case .unknown: "status: unknown"
                        default: "status: Undocumented"
                        }
                        print(status)
                    }
                    
                    print("called finishWriting \(String(describing: self?.outputFileLocation))")
#endif
                    self!.recordingStartTime = 0
                    self!.didStartSession = false
                    self!.sessionStartPTS = .invalid

                    if self!.videoWriter!.status != .completed {
#if DEBUG
                        pringVideoWriterStatus()
#endif
                        self!.videoWriter!.cancelWriting()
                        processErroringOut()
                    }
                    else {
                        Task {@MainActor [unowned self] in
                            if let strPath = self!.outputFileLocation?.path {
                                if FileManager.default.fileExists(atPath: strPath) {
                                    do {
                                        try await PHPhotoLibrary.shared().performChanges({@Sendable in
                                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self!.outputFileLocation!)
                                        })
                    #if DEBUG
                                        print("saved")
                    #endif
                                        let fetchOptions = PHFetchOptions()
                                        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                                    }
                                    catch let error {
#if DEBUG
                                        print(error.localizedDescription)
                                        pringVideoWriterStatus()
#endif
                                        processErroringOut()                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            frames = 0
        }
    }
    
    func canWrite() -> Bool {
        return isRecording && videoWriter != nil && videoWriter?.status == .writing
    }
    
    //video file location method
    @MainActor func videoFileLocation() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("videoFile")).appendingPathExtension("mp4")
        do {
            if FileManager.default.fileExists(atPath: videoOutputUrl.path) {
                try FileManager.default.removeItem(at: videoOutputUrl)
#if DEBUG
                print("file removed")
#endif
            }
        } catch {
#if DEBUG
            print(error)
#endif
        }
        
        return videoOutputUrl
    }
    
    @MainActor func setUpWriter() {
        
        do {
            if videoWriter != nil {
                videoWriter?.cancelWriting()
            }
            
            outputFileLocation = videoFileLocation()
            videoWriter = try AVAssetWriter(outputURL: outputFileLocation!, fileType: AVFileType.mp4)
            
            // add video input
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : frameWidth,
                AVVideoHeightKey : frameHeight,
                AVVideoCompressionPropertiesKey : [
                    AVVideoAverageBitRateKey : 2300000,
                ],
            ])
            
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: frameWidth,
                kCVPixelBufferHeightKey as String: frameHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            if let canAdd = videoWriter?.canAdd(videoWriterInput!), canAdd {
                videoWriter?.add(videoWriterInput!)
            } else {
#if DEBUG
                print("no input added")
#endif
            }
            
            // Apply portrait transform if needed
            if isPortrait {
                videoWriterInput?.transform = CGAffineTransform(rotationAngle: .pi / 2)
            } else {
                videoWriterInput?.transform = .identity
            }
            
            // add audio input
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: [
                AVFormatIDKey : kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey : 2,
                AVSampleRateKey : 44100.0,
                AVEncoderBitRateKey: 192000
            ])
            
            audioWriterInput?.expectsMediaDataInRealTime = true
            
            if let canAdd = videoWriter?.canAdd(audioWriterInput!), canAdd {
                videoWriter?.add(audioWriterInput!)
#if DEBUG
                print("audio input added to writer")
#endif
            }
            
            videoWriter?.startWriting()
            // Defer starting the session until first video sample
            didStartSession = false
            sessionStartPTS = .invalid
            basePTS = .invalid
            frameIndex = 0
            
            recorded = 0
            timeScale = 60
            
            if let formatDesc = frontCamera?.activeFormat.formatDescription {
                let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
                // keep existing width/height but try to infer nominal fps
                if let range = frontCamera?.activeVideoMinFrameDuration, range.timescale != 0 {
                    nominalFrameDuration = range
                } else {
                    nominalFrameDuration = CMTime(value: 1, timescale: 30)
                }
                // Ensure adaptor attributes match current dimensions
                frameWidth = Int(dims.width)
                frameHeight = Int(dims.height)
            }
        } catch let error {
#if DEBUG
            debugPrint(error.localizedDescription)
#endif
        }
    }
    
    private func startEncodingLoop() {
        guard !encodingActive else { return }
        encodingActive = true

        // Reset timing
        basePTS = .invalid
        frameIndex = 0

        let timer = DispatchSource.makeTimerSource(queue: assetWriteQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.drainQueues()
        }
        timer.resume()
        encodingTimer = timer
    }

    private func stopEncodingLoop() {
        encodingActive = false
        encodingTimer?.cancel()
        encodingTimer = nil
    }

    private func enqueueVideo(_ sampleBuffer: CMSampleBuffer) {
        // Perform stylization off the capture thread
        prepareQueue.async { [unowned self] in
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Stylize once
            let stylised = self.stylizeFrame(imageBuffer)
            let outBuf: CVPixelBuffer
            if let b = stylised.buf {
                outBuf = b
            } else {
                outBuf = imageBuffer
            }

            // Update preview with stylized image if available, else fallback
            if let ui = stylised.ui {
                DispatchQueue.main.async { [weak self] in
                    self?.didOutputNewImage(ui)
                }
            } else {
                let ci = CIImage(cvPixelBuffer: imageBuffer)
                let ui = UIImage(ciImage: ci)
                DispatchQueue.main.async { [weak self] in
                    self?.didOutputNewImage(ui)
                }
            }

            // If recording, enqueue the stylized buffer for encoding
            if self.isRecording {
                if self.videoQueue.count >= self.videoQueueMaxCount {
                    _ = self.videoQueue.removeFirst()
                }
                let queued = QueuedVideoSample(pixelBuffer: outBuf, sampleBuffer: sampleBuffer, previewImage: stylised.ui)
                self.videoQueue.append(queued)
            }
        }
    }

    private func enqueueAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        if !didStartSession { return }
        if audioQueue.count >= audioQueueMaxCount {
            _ = audioQueue.removeFirst()
        }
        audioQueue.append(sampleBuffer)
    }
    
    private func render(ciImage: CIImage, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        ciContext.render(ciImage, to: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    private func drainQueues() {
        guard canWrite(), encodingActive else { return }

        // Ensure inputs are ready before attempting appends
        let canPushVideo = videoWriterInput?.isReadyForMoreMediaData ?? false
        let canPushAudio = audioWriterInput?.isReadyForMoreMediaData ?? false

        // Process at most a few items per tick to keep latency bounded
        var processedVideo = 0
        var processedAudio = 0

        // Video
        if canPushVideo {
            while processedVideo < 4, !videoQueue.isEmpty {
                let queued = videoQueue.removeFirst()
                processVideoSample(queued)
                processedVideo += 1
            }
        }

        // Audio
        if canPushAudio {
            while processedAudio < 8, !audioQueue.isEmpty {
                let sampleBuffer = audioQueue.removeFirst()
                processAudioSample(sampleBuffer)
                processedAudio += 1
            }
        }
    }

    private func processVideoSample(_ queued: QueuedVideoSample) {
        let sampleBuffer = queued.sampleBuffer
        let outBuf = queued.pixelBuffer

        // Prefer the sample buffer PTS; fall back to monotonic frame count
        let samplePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pts: CMTime
        if samplePTS.isValid {
            if !basePTS.isValid { basePTS = samplePTS }
            pts = samplePTS
        } else {
            if !basePTS.isValid { basePTS = .zero; frameIndex = 0 }
            pts = CMTimeAdd(basePTS, CMTimeMultiply(nominalFrameDuration, multiplier: Int32(frameIndex)))
            frameIndex += 1
        }
        
        // Start writer session at first video PTS
        if !didStartSession {
            if pts.isValid {
                videoWriter?.startSession(atSourceTime: pts)
                sessionStartPTS = pts
                didStartSession = true
            }
        }

        // Ensure buffer matches adaptor's pixel format and size by rendering into pool buffer
        guard let adaptor = pixelBufferAdaptor, let pool = adaptor.pixelBufferPool else { return }
        var poolBufferOpt: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBufferOpt)
        if status != kCVReturnSuccess { return }
        guard let poolBuffer = poolBufferOpt else { return }

        // Create CIImage from the stylized buffer and render into pool buffer
        let ci = CIImage(cvPixelBuffer: outBuf)
        render(ciImage: ci, into: poolBuffer)

        writerLock.lock()
        let success = adaptor.append(poolBuffer, withPresentationTime: pts)
        writerLock.unlock()

        if !success {
            Task { @MainActor [weak self] in
                if !(self?.showError ?? false) {
                    self?.erroredOut = true
                    self?.showError = true
                }
            }
        }
    }

    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        // Only append audio after the session has started with first video frame
        guard didStartSession else { return }
        writerLock.lock()
        let ok = audioWriterInput?.append(sampleBuffer) ?? false
        writerLock.unlock()
        if !ok {
            Task { @MainActor [weak self] in
                if !(self?.showError ?? false) {
                    self?.erroredOut = true
                    self?.showError = true
                }
            }
        }
    }
}

//MARK: - Sample buffer delegates
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == cameraOutput {
            // Enqueue; preview will be updated after stylization inside enqueueVideo
            enqueueVideo(sampleBuffer)
        } else if output == mikeOutput {
            if isRecording {
                enqueueAudio(sampleBuffer)
            }
        }
    }
}

extension CameraController:  AVCaptureAudioDataOutputSampleBufferDelegate {
    // Already...
}

extension CMSampleBuffer: @unchecked @retroactive Sendable {}

