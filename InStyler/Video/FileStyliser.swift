//
//  FileStyliser.swift
//  InStyler
//
//  Created by Denis Dzyuba on 1/5/2024.
//

import Foundation
import CoreML
@preconcurrency import AVFoundation
import Vision
import CoreMedia
import CoreVideo
import CoreImage
import VideoToolbox

actor FileStyliser {
    private let dims = CGFloat(512)
    private let dim = 512
    
    private let tmpPath = "/videoFile.mp4"
    
    private var movie : AVAsset? = nil
    private var videoWriter: AVAssetWriter? // For the output file
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var session: VTPixelTransferSession? = nil
    private var pixelBufferPool: CVPixelBufferPool? = nil
    
    private var frames: Int64 = 0
    
    private var outputFileLocation: URL?
    
    private var audioBitRate = 192000
    
    private var context = CIContext()
    private var scaledBuffer: CVPixelBuffer? = nil
    private var model: VNCoreMLModel? = nil
    
    private var tracks: [AVAssetTrack]? = nil
    
    var frameCount: Int64 {
        get {
            return frames
        }
    }
    
    nonisolated private let documents: [String] = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    
    nonisolated var destinationURL: URL {
        
        if documents.isEmpty {
            #if DEBUG
            print("Could not find the Documents path")
            #endif
            return URL(fileURLWithPath: "")
        }
        let path = documents[0] + tmpPath
        return URL(fileURLWithPath: path)
    }
    
    nonisolated var destinationFileExists: Bool {
        if documents.isEmpty {
            return false
        }
        let path = documents[0] + tmpPath
        return FileManager.default.fileExists(atPath: path)
    }
    
    init(for file: URL, model: MLModel?) {
        movie = AVAsset(url: file)
        let scaledBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32ARGB) as AnyObject,
            kCVPixelBufferWidthKey: dims as AnyObject,
            kCVPixelBufferHeightKey: dims as AnyObject
        ]
        let status: CVReturn = CVPixelBufferCreate(kCFAllocatorDefault, dim, dim, kCVPixelFormatType_32ARGB, scaledBufferAttributes as CFDictionary, &scaledBuffer)
        
        guard status == kCVReturnSuccess else {
            fatalError("Could not create a scale buffer")
        }
        // change to the proper model selection
        guard let mlModel = model else {
            fatalError("Could not initialise the ML model")
        }
        
        guard let vncModel = try? VNCoreMLModel(for: mlModel) else {
            fatalError("Could not use the ML model")
        }
        self.model = vncModel
    }
    
    func loadTracks() async {
        frames = 0
        if let movie = self.movie {
            nonisolated(unsafe) let movieNoError = movie
            guard let tracks = try? await movieNoError.load(.tracks) else {
                fatalError("Could not load the movie")
            }
            self.tracks = tracks
        }
    }
    
    func stylise(reportOnEvery _frames: Int = 0, progress: @MainActor @escaping (Int, Float, Bool, String)->Void) async {
        guard let tracks = self.tracks else {
            return
        }
        
        var frames = _frames
#if DEBUG
        print("\(tracks.count) track(s).")
#endif
        guard tracks.count > 0 else {
#if DEBUG
            print("No tracks in this file.")
#endif
            return
        }
        
        guard let movie = self.movie else {
#if DEBUG
            print("Something is BADLY wrong with the movie.")
#endif
            return
        }
        
        if let reader = try? AVAssetReader(asset: movie) {
            let videoIdx = tracks.firstIndex(where: {asset in asset.mediaType == .video})
            let audioIdx = tracks.firstIndex(where: {asset in asset.mediaType == .audio})
            
            var videoTrack: AVAssetReaderTrackOutput? = nil
            var audioTrack: AVAssetReaderTrackOutput? = nil
            var frameSize = CGSize()
            var frameRate: Float = 0.0
            var trackTransform = CGAffineTransform()
            
            if videoIdx != nil {
                let track = tracks[videoIdx!]
                if let params = try? await track.load(.nominalFrameRate, .naturalSize, .preferredTransform) {
                    frameRate = params.0.rounded(.up)
                    if frames <= 0 {
                        frames = Int(frameRate)
                    }
                    frameSize = params.1
                    trackTransform = params.2
                    
                    let videoTrackOut = AVAssetReaderTrackOutput(track: track, outputSettings:
                                                                    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                                                     kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
                                                                    ])
                    videoTrackOut.alwaysCopiesSampleData = true
                    
                    if reader.canAdd(videoTrackOut) {
                        reader.add(videoTrackOut)
                        videoTrack = videoTrackOut
                    }
                    else {
#if DEBUG
                        print("No can add video.")
#endif
                    }
                }
            }
            else {
#if DEBUG
                print("No video tracks in this file.")
#endif
                return
            }
            
            if audioIdx != nil {
                let audio = tracks[audioIdx!]
                if let rate = try? await audio.load(.estimatedDataRate) {
                    audioBitRate = Int((rate / 1000.0).rounded(.up) * 1000.0)
                }
                let audioTrackOut = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                    AVFormatIDKey : kAudioFormatLinearPCM,
                    AVNumberOfChannelsKey : 2,
                ])
                
                audioTrackOut.alwaysCopiesSampleData = true
                
                if (reader.canAdd(audioTrackOut)) {
                    reader.add(audioTrackOut)
                    audioTrack = audioTrackOut
#if DEBUG
                    print("Added audio track output")
#endif
                }
                else {
#if DEBUG
                    print("No can add audio.")
#endif
                }
            }
            
            outputFileLocation = videoFileLocation()
            setUpWriter(size: frameSize, bitrate: frameRate, transform: trackTransform)
            
            guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session) == noErr else {
                fatalError("Failed to create pixel transfer")
            }
            
            reader.startReading()
            
            videoWriter?.startWriting()
            videoWriter?.startSession(atSourceTime: CMTime.zero)
            
            var bufCount = 0
            
            var doneReadingVideo = false
            var doneReadingAudio = false
            var stylising = true
            
            while true {
                if Task.isCancelled {
                    doneReadingAudio = true
                    audioWriterInput?.markAsFinished()
                    break
                }
                
                if let videoTrack {
                    if videoWriterInput!.isReadyForMoreMediaData && !doneReadingVideo {
                        if let buf = videoTrack.copyNextSampleBuffer() {
                            // We've got our sample buffer!
                            if let imageBuffer = CMSampleBufferGetImageBuffer(buf) {
                                let newPTS = buf.outputPresentationTimeStamp
                                
                                if let stylisedBuf = stylizeFrame(imageBuffer, originalSize: frameSize) {
                                    if !pixelBufferAdaptor!.append(stylisedBuf, withPresentationTime: newPTS) {
                                        await progress(Int(bufCount), Float(bufCount) / frameRate, true, "Failed to add the stylised frame to the output")
                                        break
                                    }
                                    else {
                                        //call the callback for a stylised image
                                        //every frames frames
                                        if bufCount % frames == 0 {
                                            await progress(Int(bufCount), Float(bufCount) / frameRate, true, "")
                                        }
                                    }
                                }
                                else {
                                    if !pixelBufferAdaptor!.append(imageBuffer, withPresentationTime: newPTS) {
                                        await progress(Int(bufCount), Float(bufCount) / frameRate, false, "Failed to copy the frame to the output")
                                        break
                                    }
                                    else {
                                        stylising = false
                                        //call the callback for a copied image:
                                        //if that happens, the user should see a warning that some frames
                                        //aren't going to be stylised
                                        if bufCount % frames == 0 {
                                            await progress(Int(bufCount), Float(bufCount) / frameRate, false, "")
                                        }
                                    }
                                }
                            }
                            else {
                                let errorStr = videoWriter?.error?.localizedDescription ?? ""
                                await progress(Int(bufCount), Float(bufCount) / frameRate, false, "Failed to load source's samples as an image buffer" + (errorStr != "" ? " : \(errorStr)" : ""))
                                break
                            }
                            
                            bufCount += 1
                        }
                        else {
                            // We're finished reading video data
                            doneReadingVideo = true
                        }
                    }
                }
                else {
                    //Error: no video, and we need it
                    break
                }
                
                if let audioTrack {
                    //print("Audio track is there")
                    if audioWriterInput!.isReadyForMoreMediaData && !doneReadingAudio {
                        //print("Ok to write audio")
                        if let aud = audioTrack.copyNextSampleBuffer() {
                            if let added = audioWriterInput?.append(aud) {
                                if (!added) {
                                    //error: could not add audio buffer
                                }
                            }
                        }
                        else {
                            // We've finished reading the audio data
                            doneReadingAudio = true
                            audioWriterInput?.markAsFinished()
                        }
                    }
                }
                else {
                    // The file didn't contain any audio data
                    doneReadingAudio = true
                    audioWriterInput?.markAsFinished()
                }
                
                if doneReadingAudio && doneReadingVideo {
                    let success = reader.status == .reading || reader.status == .completed
                    if success {
                        await progress(Int(bufCount - 1), Float(bufCount - 1) / frameRate, stylising, "")
                        reader.cancelReading()
                    }
                    break
                }
            }
            
            videoWriterInput?.markAsFinished()
            
            func finishWriting() async {
                Task { @MainActor in
                    await videoWriter?.finishWriting()
                }
            }
            
            await finishWriting()
            
            reader.cancelReading()
            print("Out")
        }
        else {
            fatalError("Could not create a reader")
        }
    }
    
    private func videoFileLocation() -> URL {
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
    
    private func setUpWriter(size: CGSize, bitrate: Float, transform: CGAffineTransform) {
        
        do {
            outputFileLocation = videoFileLocation()
            videoWriter = try AVAssetWriter(outputURL: outputFileLocation!, fileType: AVFileType.mp4)
            
            // add video input
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                AVVideoCodecKey : AVVideoCodecType.h264,
                AVVideoWidthKey : size.width,
                AVVideoHeightKey : size.height,
            ])
            videoWriterInput?.transform = transform
            
            let sourceBufferAttributes : [String : Any] = [
                kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String : size.width,
                kCVPixelBufferHeightKey as String : size.height]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            if let canAdd = videoWriter?.canAdd(videoWriterInput!), canAdd {
                videoWriter?.add(videoWriterInput!)
                //print("video input added")
            } else {
#if DEBUG
                print("no video input added")
#endif
            }
            
            // add audio input
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: [
                AVFormatIDKey : kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey : 2,
                AVSampleRateKey : 44100.0,
                AVEncoderBitRateKey: audioBitRate
            ])
            
            if let canAdd = videoWriter?.canAdd(audioWriterInput!), canAdd {
                videoWriter?.add(audioWriterInput!)
#if DEBUG
                print("audio input added")
#endif
            }
            else {
#if DEBUG
                print("no audio input added")
                if let what = videoWriter?.error?.localizedDescription {
                    print(what)
                }
#endif
            }
        } catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    static func getModel() -> MLModelConfiguration {
        let mcfg = MLModelConfiguration()
        mcfg.computeUnits = .all
        return mcfg
    }
    
    private func stylizeFrame(_ imageBuffer: CVPixelBuffer, originalSize: CGSize) -> CVPixelBuffer? {
        let originalSize = CVImageBufferGetEncodedSize(imageBuffer)
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer).transformed(by: .init(scaleX: dims / originalSize.width, y: dims / originalSize.height))
        context.render(ciImage, to: scaledBuffer!)
        
        let request = VNCoreMLRequest(model: model!)
        
        try? VNImageRequestHandler(cvPixelBuffer: scaledBuffer!, options: [.ciContext: context]).perform([request])
        
        guard let result = (request.results?.first as? VNPixelBufferObservation) else {
#if DEBUG
            print("Vision request failed")
#endif
            return nil
        }
        
        let tmp = CIImage(cvPixelBuffer: result.pixelBuffer)
        var resBuffer: CVPixelBuffer? = nil
        let scaledBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32ARGB) as AnyObject,
            kCVPixelBufferWidthKey: originalSize.width as AnyObject,
            kCVPixelBufferHeightKey: originalSize.height as AnyObject
        ]
        let status: CVReturn = CVPixelBufferCreate(kCFAllocatorDefault, Int(originalSize.width), Int(originalSize.height), kCVPixelFormatType_32ARGB, scaledBufferAttributes as CFDictionary, &resBuffer)
        
        guard status == kCVReturnSuccess else {
            fatalError("Could not create a stylised frame buffer")
        }
        context.render(tmp.transformed(by: .init(scaleX: originalSize.width / dims, y: originalSize.height / dims)), to: resBuffer!)
        return resBuffer
    }
}

extension AVAssetTrack: @unchecked @retroactive Sendable {}
extension AVAssetWriter: @unchecked @retroactive Sendable {}
