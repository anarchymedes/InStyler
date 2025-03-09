//
//  PhotoModel.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/3/2025.
//  Based on the code from this Apple tutorial:
//  doc://com.apple.documentation/tutorials/sample-apps/CapturingPhotos-BrowsePhotos
//

import AVFoundation
import SwiftUI

protocol CaptureCompletionDelegate {
    func setImageAndClose(_ image: UIImage?, _ presented: Bool)
}

@MainActor final class PhotoDataModel: ObservableObject, @unchecked Sendable {
    let camera = PhotoCamera()
    let photoCollection = PhotoCollection(smartAlbum: .smartAlbumUserLibrary)
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    
    @Published var isCameraActive: Bool = true
    
    @AppStorage("chosenStyle") var chosenStyle: Int?
    @AppStorage("loResPhoto") private var loResPhoto: Bool = false
    
    var completionDelegate: CaptureCompletionDelegate?
    
    var isPhotosLoaded = false
    
    init() {
        Task {
            await handleCameraPreviews()
        }
        
        Task {
            await handleCameraPhotos()
        }
    }
    
    func loadPhotos() async {
        guard !isPhotosLoaded else { return }
        
        let authorized = await PhotoLibrary.checkAuthorization()
        guard authorized else {
            print("Photo library access was not authorized.")
            return
        }
        
        Task {
            do {
                try await self.photoCollection?.load()
            } catch let error {
                print("Failed to load photo collection: \(error.localizedDescription)")
            }
            self.isPhotosLoaded = true
        }
    }

    private func unpackPhoto(_ photo: AVCapturePhoto) -> PhotoData? {
        guard let imageData = photo.fileDataRepresentation() else { return nil }

        guard let previewCGImage = photo.previewCGImageRepresentation(),
           let metadataOrientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
              let cgImageOrientation = CGImagePropertyOrientation(rawValue: metadataOrientation) else { return nil }
        let imageOrientation = Image.Orientation(cgImageOrientation)
        let thumbnailImage = Image(decorative: previewCGImage, scale: 1, orientation: imageOrientation)
        
        let photoDimensions = photo.resolvedSettings.photoDimensions
        let imageSize = (width: Int(photoDimensions.width), height: Int(photoDimensions.height))
        let previewDimensions = photo.resolvedSettings.previewDimensions
        let thumbnailSize = (width: Int(previewDimensions.width), height: Int(previewDimensions.height))
        
        return PhotoData(thumbnailImage: thumbnailImage, thumbnailSize: thumbnailSize, imageData: imageData, imageSize: imageSize)
    }

    func handleCameraPhotos() async {
        let unpackedPhotoStream = camera.photoStream
            .compactMap {
                nonisolated(unsafe) let inside = $0
                return await self.unpackPhoto(inside)
            }
        
        for await photoData in unpackedPhotoStream {
            var useOriginal = false
            if let uiImage = UIImage(data: photoData.imageData) {
                if let cgBuffer = uiImage.toBuffer() {
                    if let stylisedBuf = stylizePicture(cgBuffer, chosenStyle: chosenStyle, forImages: !loResPhoto){
                        let stylised = UIImage.imageFromCVPixelBuffer(pixelBuffer: stylisedBuf)
                        if let resized = stylised?.resizeTo(size: uiImage.size) {
                            savePhoto(imageData: resized.heicData() ?? photoData.imageData)
                            Task {@MainActor in
                                completionDelegate?.setImageAndClose(resized, false)
                            }
                        }
                        else {
                            useOriginal = true
                        }
                    }
                    else {
                        useOriginal = true
                    }
                }
                else {
                    useOriginal = true
                }
            }
            else {
                useOriginal = true
            }
            
            if useOriginal {
                savePhoto(imageData: photoData.imageData)
                Task {@MainActor in
                    completionDelegate?.setImageAndClose(nil, false)
                }
            }
        }
    }

    func handleCameraPreviews() async {
        let imageStream = camera.previewStream
            .map { $0.image }

        for await image in imageStream {
            Task { @MainActor in
                viewfinderImage = image
            }
        }
    }
    
    func savePhoto(imageData: Data) {
        Task {
            do {
                try await photoCollection?.addImage(imageData)
                print("Added image data to photo collection.")
            } catch let error {
                print("Failed to add image to photo collection: \(error.localizedDescription)")
            }
        }
    }
}

fileprivate struct PhotoData {
    var thumbnailImage: Image
    var thumbnailSize: (width: Int, height: Int)
    var imageData: Data
    var imageSize: (width: Int, height: Int)
}

fileprivate extension CIImage {
    var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}

fileprivate extension Image.Orientation {

    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
