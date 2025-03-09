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
        
        //MARK: - Configure capture device
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
                self.cameraOutput!.alwaysDiscardsLateVideoFrames = true // To drop the frames we can't process on time
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
            
            audioWriterInput?.markAsFinished()
            videoWriterInput?.markAsFinished()
            #if DEBUG
            print("marked as finished")
            #endif
            
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
            
            let sourceBufferAttributes = [
                (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32ARGB),
                (kCVPixelBufferWidthKey as String): Float(frameWidth),
                (kCVPixelBufferHeightKey as String): Float(frameHeight)] as [String : Any]
            
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
            videoWriter?.startSession(atSourceTime: CMTime.init(seconds: CACurrentMediaTime(), preferredTimescale: 1))
            recordingStartTime = CACurrentMediaTime()
            recorded = 0
            timeScale = 60
        } catch let error {
#if DEBUG
            debugPrint(error.localizedDescription)
#endif
        }
    }
}

//MARK: - Sample buffer delegates
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate  {
    private var VIDEO_WAIT_TIMER: Int {return 10_000_000_000}
    private var VIDEO_RETRIES: Int {return 10}
    
    private var AUDIO_WAIT_TIMER: Int {return 10_000_000_000}
    private var AUDIO_RETRIES: Int {return 10}

    private func recordFrame(_ output: AVCaptureOutput, _ sampleBuffer: CMSampleBuffer, _ toDisplay: Bool) -> Bool {
        
        var retVal = false
        
        @Sendable func setRetVal(_ newVal: Bool) {
            Task {@MainActor in
                retVal = newVal
            }
        }

        retVal = autoreleasepool {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
            
            let stylised = self.stylizeFrame(imageBuffer)
            let image = stylised.ui
            let ciImage = CIImage(cvPixelBuffer: stylised.buf ?? imageBuffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return false }
            
            //MARK: - AVWriteAsset stuff
            let writable = self.canWrite()
            if writable, output == self.cameraOutput {
                
                if isRecording {
                    assetWriteQueue.async {[unowned self] in // We don't want our waiting for isReadyForMoreMediaData to interfere with the incoming frames, so we put it on a different thread
                        if let pixelBufferPool = self.pixelBufferAdaptor?.pixelBufferPool {
                            
                            let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
                            let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(
                                kCFAllocatorDefault,
                                pixelBufferPool,
                                pixelBufferPointer
                            )
                            
                            if (status == 0) {
                                for _ in 0...VIDEO_WAIT_TIMER { // Wait for the writer to become accessible: not forever (not 'while true'), because this task isn't cancellable
                                    if let ready = self.pixelBufferAdaptor?.assetWriterInput.isReadyForMoreMediaData, let session = self.captureSession {
                                        if ready && session.isRunning {
                                            let frameBuf = stylised.buf
                                            
                                            self.frames += 1
                                            
                                            let recordingTime = CACurrentMediaTime() - recordingStartTime
                                            let realFrameDuration = recordingTime / Double(frames)
                                            
                                            let presentationTime = CMTime.init(seconds: recordingStartTime, preferredTimescale: 1) + CMTimeMake(value: frames, timescale: Int32(1.0 / realFrameDuration))
                                            
                                            writerLock.lock() // The extra insurance
                                            prepareQueue.sync { // Writing to the pixel buffer adaptor MUST happen on ONE AND THE SAME THREAD!!!
                                                var bErroredOut = false // Whether or not we want to show the error message in the UI
                                                for _ in  0...VIDEO_RETRIES { // If the writing has failed, we retry VIDEO_RETRIES times
                                                    guard let appendSucceeded = self.pixelBufferAdaptor?.append(
                                                        frameBuf!,
                                                        withPresentationTime: presentationTime
                                                    ) else {fatalError("Could not append a buffer to the buffer adaptor")}
                                                    
                                                    if appendSucceeded {
                                                        bErroredOut = false
                                                        setRetVal(true)
                                                        break
                                                    } else {
                                                        if let error = self.videoWriter?.error {
#if DEBUG
                                                            print("something's wrong (video): \(error.localizedDescription)")
                                                            let status = switch self.videoWriter!.status {
                                                            case .completed: "status: completed"
                                                            case .writing: "status: writing"
                                                            case .cancelled: "status: cancelled"
                                                            case .failed: "status: failed"
                                                            case .unknown: "status: unknown"
                                                            default: "status: Undocumented"
                                                            }
                                                            print(status)
#endif
                                                            bErroredOut = self.videoWriter!.status != .writing
                                                            if (self.videoWriter!.status != .failed && self.videoWriter!.status != .writing) ||
                                                                self.videoWriter!.status == .writing {
                                                                break
                                                            }
                                                        }
                                                        else {
#if DEBUG
                                                            print("something's wrong (video)")
#endif
                                                            bErroredOut = true
                                                            break
                                                        }
                                                    }
                                                }
                                                
                                                if bErroredOut {
                                                    Task {@MainActor [weak self] in
                                                        if !(self?.showError ?? false) {
                                                            self?.erroredOut = true
                                                            self?.showError = true
                                                        }
                                                    }
                                                }
                                            }//prepareQueue.sync
                                            writerLock.unlock()
                                            
                                            break // for _ in 0...10_000_000_000
                                        }
                                        else if !session.isRunning {
                                            break // for _ in 0...10_000_000_000
                                        }
                                        break // for _ in 0...10_000_000_000
                                    }
                                }
                            }
                            else {
#if DEBUG
                                print("Could not allocate pixel buffer")
#endif
                                Task {@MainActor [weak self] in
                                    if !(self?.showError ?? false) {
                                        self?.erroredOut = true
                                        self?.showError = true
                                    }
                                }
                            }
                            pixelBufferPointer.deinitialize(count: 1)
                            pixelBufferPointer.deallocate()
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {[unowned self] in
                if toDisplay {
                    // the final picture is here, we call the completion block
                    let toShow = image
                    let cg  = cgImage
                    self.didOutputNewImage(toShow ?? UIImage(cgImage: cg))
                }
            }
            return retVal
        }// autoreleasepool

        return retVal
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == cameraOutput {
            if recordFrame(output, sampleBuffer, true) {
                frames += 1
            }
        }
        else {
            // Audio data?
            if canWrite() && output == mikeOutput {
                assetWriteQueue.async {[unowned self] in // We don't want our waiting for isReadyForMoreMediaData to interfere with the incoming frames, so we put it on a different thread
                    for _ in 0...AUDIO_WAIT_TIMER { // Wait for the writer to become accessible: not forever (not 'while true'), because this task isn't cancellable
                        if let isReady = (audioWriterInput?.isReadyForMoreMediaData), isReady, let session = self.captureSession, session.isRunning {
                            // write audio buffer
                            writerLock.lock() // The extra insurance
                            prepareQueue.sync {// Appending the sample buffer MUST happen on ONE AND THE SAME THREAD!!!
                                // If the writing has failed, we retry 10 times
                                var bErroredOut = false  // Whether or not we want to show the error message in the UI
                                for _ in 0...AUDIO_RETRIES {
                                    if let success = self.audioWriterInput?.append(sampleBuffer) {
                                        if !success {
                                            if let error = self.videoWriter?.error {
#if DEBUG
                                                print("something's wrong (audio): \(error.localizedDescription)")
                                                let status = switch self.videoWriter!.status {
                                                case .completed: "status: completed"
                                                case .writing: "status: writing"
                                                case .cancelled: "status: cancelled"
                                                case .failed: "status: failed"
                                                case .unknown: "status: unknown"
                                                default: "status: Undocumented"
                                                }
                                                print(status)
#endif
                                                bErroredOut = self.videoWriter!.status != .writing
                                                if (self.videoWriter!.status != .failed && self.videoWriter!.status != .writing) ||  
                                                    self.videoWriter!.status == .writing {
                                                    break
                                                }
                                            }
                                            else {
#if DEBUG
                                                print("something's wrong (audio)")
#endif
                                                bErroredOut  = true
                                                break
                                            }
                                        }
                                        else {
                                            // We've successfully recored the frame: no more looping
                                            bErroredOut = false
                                            break
                                        }
                                    }
                                }
                                
                                if bErroredOut {
                                    Task{@MainActor [weak self] in
                                        if !(self?.showError ?? false) {
                                            self?.erroredOut = true
                                            self?.showError = true
                                        }
                                    }
                                }
                            }
                            writerLock.unlock()
                            break
                        }
                    }
                }
            }
        }
    }
}

extension CameraController:  AVCaptureAudioDataOutputSampleBufferDelegate {
    // Already...
}

extension CMSampleBuffer: @unchecked @retroactive Sendable {}
