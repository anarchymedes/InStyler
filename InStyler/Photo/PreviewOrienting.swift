//
//  PreviewOrienting.swift
//  InStyler
//
//  Created by InStyler on 2026-02-06.
//

import CoreImage
import CoreGraphics
import Foundation

public protocol PreviewOrienting: Sendable {
    func orientedPreviewImage(_ image: CIImage, angleDegrees: CGFloat, mirrored: Bool, targetSize: CGSize) -> CIImage
}

public struct DefaultPreviewOrienter: PreviewOrienting {
    
    public init() {}
    
    public func orientedPreviewImage(_ image: CIImage, angleDegrees: CGFloat, mirrored: Bool, targetSize: CGSize) -> CIImage {
        let radians = -angleDegrees * .pi / 180.0
        
        // Rotate around image center
        let imageExtent = image.extent
        let centerX = imageExtent.midX
        let centerY = imageExtent.midY
        
        var transform = CGAffineTransform(translationX: -centerX, y: -centerY)
        transform = transform.rotated(by: radians)
        
        if mirrored {
            transform = transform.scaledBy(x: -1, y: 1)
        }
        
        transform = transform.translatedBy(x: centerX, y: centerY)
        
        let rotatedImage = image.transformed(by: transform)
        let rotatedExtent = rotatedImage.extent
        
        // Calculate scale to aspect-fit into targetSize
        let scaleX = targetSize.width / rotatedExtent.width
        let scaleY = targetSize.height / rotatedExtent.height
        let scale = min(scaleX, scaleY)
        
        // Apply scale
        let scaledTransform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = rotatedImage.transformed(by: scaledTransform)
        
        // Calculate translation to center scaled image within target rectangle
        let scaledExtent = scaledImage.extent
        
        let translateX = (targetSize.width - scaledExtent.width) / 2.0 - scaledExtent.origin.x
        let translateY = (targetSize.height - scaledExtent.height) / 2.0 - scaledExtent.origin.y
        
        let centeredTransform = CGAffineTransform(translationX: translateX, y: translateY)
        
        let finalImage = scaledImage.transformed(by: centeredTransform)
        
        return finalImage
    }
}
