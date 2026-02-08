//
//  PhotoCamera.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/3/2025.
//  Based on the code from this Apple tutorial:
//  doc://com.apple.documentation/tutorials/sample-apps/CapturingPhotos-BrowsePhotos
//
@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import UIKit
import SwiftUI

class PhotoCamera: NSObject, @unchecked Sendable {
    @AppStorage("chosenStyle") var chosenStyle: Int?
    
    // Strategy for orienting and scaling preview frames
    var previewOrienter: PreviewOrienting = DefaultPreviewOrienter()
    
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured = false
    private var deviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue: DispatchQueue!
    
    private var allCaptureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera, .builtInDualWideCamera], mediaType: .video, position: .unspecified).devices
    }
    
    private var frontCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices
            .filter { $0.position == .front }
    }
    
    private var backCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices
            .filter { $0.position == .back }
    }
    
    private var captureDevices: [AVCaptureDevice] {
        var devices = [AVCaptureDevice]()
        #if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
        devices += allCaptureDevices
        #else
        if let backDevice = backCaptureDevices.first {
            devices += [backDevice]
        }
        if let frontDevice = frontCaptureDevices.first {
            devices += [frontDevice]
        }
        #endif
        return devices
    }
    
    private var availableCaptureDevices: [AVCaptureDevice] {
        captureDevices
            .filter( { $0.isConnected } )
            .filter( { !$0.isSuspended } )
    }
    
    private var captureDevice: AVCaptureDevice? {
        didSet {
            guard let captureDevice = captureDevice else { return }
            print("Using capture device: \(captureDevice.localizedName)")
            sessionQueue.async {
                self.updateSessionForCaptureDevice(captureDevice)
            }
        }
    }
    
    var isRunning: Bool {
        captureSession.isRunning
    }
    
    var isUsingFrontCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return frontCaptureDevices.contains(captureDevice)
    }
    
    var isUsingBackCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return backCaptureDevices.contains(captureDevice)
    }

    private var addToPhotoStream: ((AVCapturePhoto) -> Void)?
    
    private var addToPreviewStream: ((CIImage) -> Void)?
    
    var isPreviewPaused = false
    
    // Size (in points) of the preview surface; update this from the hosting view.
    // Defaults to 1080x1920 portrait if not set.
    var previewTargetSize: CGSize = CGSize(width: 1080, height: 1920)
    
    lazy var previewStream: AsyncStream<CIImage> = {
        AsyncStream { continuation in
            addToPreviewStream = { ciImage in
                let ciImageNoError = ciImage
                if !self.isPreviewPaused {
                    continuation.yield(ciImageNoError)
                }
            }
        }
    }()
    
    lazy var photoStream: AsyncStream<AVCapturePhoto> = {
        AsyncStream { continuation in
            addToPhotoStream = { photo in
                nonisolated(unsafe) let photoNoError = photo
                continuation.yield(photoNoError)
            }
        }
    }()
        
    @MainActor override init() {
        super.init()
        initialize()
    }
    
    @MainActor private func initialize() {
        sessionQueue = DispatchQueue(label: "session queue")
        
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(updateForDeviceOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    private func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {
        
        var success = false
        
        self.captureSession.beginConfiguration()
        
        defer {
            self.captureSession.commitConfiguration()
            completionHandler(success)
        }
        
        guard
            let captureDevice = captureDevice,
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            print("Failed to obtain video input.")
            return
        }
        
        let photoOutput = AVCapturePhotoOutput()
                        
        captureSession.sessionPreset = AVCaptureSession.Preset.photo

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
  
        guard captureSession.canAddInput(deviceInput) else {
            print("Unable to add device input to capture session.")
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            print("Unable to add photo output to capture session.")
            return
        }
        guard captureSession.canAddOutput(videoOutput) else {
            print("Unable to add video output to capture session.")
            return
        }
        
        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        
        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.videoOutput = videoOutput
        
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        updateVideoOutputConnection()
        
        isCaptureSessionConfigured = true
        
        success = true
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("Camera access authorised.")
            return true
        case .notDetermined:
            print("Camera access not determined.")
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            print("Camera access denied.")
            return false
        case .restricted:
            print("Camera library access restricted.")
            return false
        @unknown default:
            return false
        }
    }
    
    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let error {
            print("Error getting capture device input: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }
        
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                captureSession.removeInput(deviceInput)
            }
        }
        
        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }
        
        updateVideoOutputConnection()
    }
    
    private func updateVideoOutputConnection() {
        if let videoOutput = videoOutput, let videoOutputConnection = videoOutput.connection(with: .video) {
            if videoOutputConnection.isVideoMirroringSupported {
                videoOutputConnection.isVideoMirrored = isUsingFrontCaptureDevice
            }
        }
    }
    
    private func bestMaxPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions {
        let format = device.activeFormat
        let desc = format.formatDescription
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        // Optionally clamp to a ceiling to control memory usage
        let maxWidth = Int32(min(Int(dims.width), 4032))
        let maxHeight = Int32(min(Int(dims.height), 4032))
        return CMVideoDimensions(width: maxWidth, height: maxHeight)
    }
    
    func start() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            print("Camera access was not authorized.")
            return
        }
        
        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                sessionQueue.async { [self] in
                    self.captureSession.startRunning()
                }
            }
            return
        }
        
        sessionQueue.async { [self] in
            self.configureCaptureSession { success in
                guard success else { return }
                self.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        guard isCaptureSessionConfigured else { return }
        
        if captureSession.isRunning {
            sessionQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func switchCaptureDevice() {
        if let captureDevice = captureDevice, let index = availableCaptureDevices.firstIndex(of: captureDevice) {
            let nextIndex = (index + 1) % availableCaptureDevices.count
            self.captureDevice = availableCaptureDevices[nextIndex]
        } else {
            self.captureDevice = AVCaptureDevice.default(for: .video)
        }
    }

    @MainActor private var deviceOrientation: UIDeviceOrientation {
        var orientation = UIDevice.current.orientation
        if orientation == UIDeviceOrientation.unknown {
            orientation = UIScreen.main.orientation
        }
        return orientation
    }
    
    @objc
    func updateForDeviceOrientation() {
        //TODO: Figure out if we need this for anything.
    }
    
    private func videoOrientation() -> (CGFloat?, Bool) {
        guard self.captureDevice != nil else { return (nil, false) }
        
        let rc = AVCaptureDevice.RotationCoordinator(device: self.captureDevice!, previewLayer: nil)
        return (rc.videoRotationAngleForHorizonLevelCapture, rc.device?.isPortraitEffectActive ?? false)
    }

    func takePhoto() {
        guard let photoOutput = self.photoOutput else { return }
        
        sessionQueue.async {
        
            var photoSettings = AVCapturePhotoSettings()

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            photoSettings.photoQualityPrioritization = .balanced

            // Use maxPhotoDimensions instead of deprecated high-resolution flags
            if let device = self.deviceInput?.device {
                let dims = self.bestMaxPhotoDimensions(for: device)
                photoSettings.maxPhotoDimensions = dims
            }
            
            if let photoOutputVideoConnection = photoOutput.connection(with: .video) {
                let orientation = self.videoOrientation()
                if let angle = orientation.0, photoOutputVideoConnection.isVideoRotationAngleSupported(angle) {
                    photoOutputVideoConnection.videoRotationAngle = angle
                }
            }
            
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
}

extension PhotoCamera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        addToPhotoStream?(photo)
    }
}

extension PhotoCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    //MARK: - Stylising function or a preview frame
    private func stylizeFrame(_ imageBuffer: CVPixelBuffer) -> CIImage? {
        let originalSize = CVImageBufferGetEncodedSize(imageBuffer)
        
        if let buf = stylizePicture(imageBuffer, chosenStyle: chosenStyle, forImages: false) {
            let ciFinal = CIImage(cvPixelBuffer: buf).transformed(by: .init(scaleX: originalSize.width / dims, y: originalSize.height / dims))
            
            return ciFinal
        }
        else {
            return nil
        }
        
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
//        if connection.isVideoOrientationSupported,
//           let videoOrientation = videoOrientationFor(deviceOrientation) {
//            connection.videoOrientation = videoOrientation
//        }
        // Removed per-frame rotation from connection
        
        let orientation = self.videoOrientation()
        let angle = orientation.0 ?? 0
        let mirrored = self.isUsingFrontCaptureDevice
        let baseImage = stylizeFrame(pixelBuffer) ?? CIImage(cvPixelBuffer: pixelBuffer)
        let oriented = previewOrienter.orientedPreviewImage(baseImage, angleDegrees: angle, mirrored: mirrored, targetSize: previewTargetSize)
        addToPreviewStream?(oriented)
    }
}

fileprivate extension UIScreen {

    var orientation: UIDeviceOrientation {
        let point = coordinateSpace.convert(CGPoint.zero, to: fixedCoordinateSpace)
        if point == CGPoint.zero {
            return .portrait
        } else if point.x != 0 && point.y != 0 {
            return .portraitUpsideDown
        } else if point.x == 0 && point.y != 0 {
            return .landscapeRight //.landscapeLeft
        } else if point.x != 0 && point.y == 0 {
            return .landscapeLeft //.landscapeRight
        } else {
            return .unknown
        }
    }
}

