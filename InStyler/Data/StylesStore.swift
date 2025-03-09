//
//  StylesStore.swift
//  InStyler
//
//  Created by Denis Dzyuba on 16/11/20.
//

import Foundation
import SwiftUI
import CoreML
import Vision
import VisionKit

let styles: [ImageStyle] = [
    ImageStyle(title: "Alice in Wonderland", image: "Alice", gradientColors: [Color("AliceColourLight"), Color("AliceColourDark")], description: "Your image will be styled after the colourised Sir John Tenniel's illustrations for Alice in Wonderland, by Lewis Carroll", modelSelector: 0),
    ImageStyle(title: "Altamira Bison", image: "altamira", gradientColors: [Color("AltamiraColourLight"), Color("AltamiraColourDark")], description: "Your image will be styled after the famous Altamira Bison, a cave painting from circa 20,000 BC found in the Altamira cave, Spain", modelSelector: 1),
    ImageStyle(title: "Göbekli Tepe", image: "gobeklitepe", gradientColors: [Color("GTColourLight"), Color("GTColourDark")], description: "Your image will be styled after the carvings found on the megaliths of Göbekli Tepe, an 11,000 BC shrine located near Şanlıurfa, in South-Eastern Anatolia, Türkiye", modelSelector: 2),
    ImageStyle(title: "A Hologram", image: "Hologram", gradientColors: [Color("HologramColourLight"), Color("HologramColourDark")], description: "Your image will be styled after a hologram, similar to the ones that appear in many sci-fi movies", modelSelector: 3),
    ImageStyle(title: "The Matrix", image: "Matrix", gradientColors: [Color("MatrixColourLight"), Color("MatrixColourDark")], description: "Your image will be styled after the picture operators saw when they looked directly into the Matrix", modelSelector: 4),
    ImageStyle(title: "Pencil Sketch", image: "pencil", gradientColors: [Color("PencilColourLight"), Color("PencilColourDark")], description: "Your image will be styled after a basic pencil sketch most artists make while planning a detailed work", modelSelector: 5),
]

private func getModel() -> MLModelConfiguration {
    let mcfg = MLModelConfiguration()
    mcfg.computeUnits = .all
    return mcfg
}

nonisolated(unsafe) let Matrix = (images: try! MatrixHi(configuration: getModel()), video: try! MatrixLo(configuration: getModel()))
nonisolated(unsafe) let Alice = (images: try! AliceHi(configuration: getModel()), video: try! AliceLo(configuration: getModel()))
nonisolated(unsafe) let Pencil = (images: try! PencilHi(configuration: getModel()), video: try! PencilLo(configuration: getModel()))
nonisolated(unsafe) let Altamira = (images: try! AltamiraImages(configuration: getModel()), video: try! AltamiraVideo(configuration: getModel()))
nonisolated(unsafe) let GobekliTepe = (images: try! GobekliTepePictures(configuration: getModel()), video: try! GobekliTepeVideo(configuration: getModel()))
nonisolated(unsafe) let Hologram = (images: try! HologramHi(configuration: getModel()), video: try! HologramLo(configuration: getModel()))

let dims = CGFloat(512)
let idims = Int(512)

private func setupGLobalScaledBuffer()->CVPixelBuffer?{
    var scaledBuffer: CVPixelBuffer? = nil
    let scaledBufferAttributes = [
                    kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32ARGB) as AnyObject,
                    kCVPixelBufferWidthKey: dims as AnyObject,
                    kCVPixelBufferHeightKey: dims as AnyObject
    ]
    let status: CVReturn = CVPixelBufferCreate(kCFAllocatorDefault, idims, idims, kCVPixelFormatType_32ARGB, scaledBufferAttributes as CFDictionary, &scaledBuffer)
    guard status == kCVReturnSuccess else {
        fatalError("Could not create a scale buffer")
    }
    
    return scaledBuffer
}

nonisolated(unsafe) let context = CIContext()
nonisolated(unsafe) var scaledBuffer = setupGLobalScaledBuffer()

func pickModel(chosenStyle: Int?, forImages: Bool = true)->MLModel {
    let mlModel = switch (chosenStyle) {
    case 0: forImages ? Alice.images.model : Alice.video.model
    case 1: forImages ? Altamira.images.model : Altamira.video.model
    case 2: forImages ? GobekliTepe.images.model : GobekliTepe.video.model
    case 3: forImages ? Hologram.images.model : Hologram.video.model
    case 4: forImages ? Matrix.images.model : Matrix.video.model
    case 5: forImages ? Pencil.images.model : Pencil.video.model
    default: MLModel()
    }

    return mlModel
}

func stylizePicture(_ imageBuffer: CVPixelBuffer, chosenStyle: Int?, forImages: Bool = true) -> CVPixelBuffer? {
    let originalSize = CVImageBufferGetEncodedSize(imageBuffer)
    
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

    let ciImage = CIImage(cvPixelBuffer: imageBuffer).transformed(by: .init(scaleX: dims / originalSize.width, y: dims / originalSize.height))
    context.render(ciImage, to: scaledBuffer!)

    let mlModel = switch (chosenStyle) {
    case 0: forImages ? Alice.images.model : Alice.video.model
    case 1: forImages ? Altamira.images.model : Altamira.video.model
    case 2: forImages ? GobekliTepe.images.model : GobekliTepe.video.model
    case 3: forImages ? Hologram.images.model : Hologram.video.model
    case 4: forImages ? Matrix.images.model : Matrix.video.model
    case 5: forImages ? Pencil.images.model : Pencil.video.model
    default: MLModel()
    }
    
    guard let model = try? VNCoreMLModel(for: mlModel) else { return nil }
    let request = VNCoreMLRequest(model: model)
    try? VNImageRequestHandler(cvPixelBuffer: scaledBuffer!, options: [.ciContext: context]).perform([request])
    guard let result = (request.results?.first as? VNPixelBufferObservation) else {
        return nil
    }
    
    return result.pixelBuffer
}

