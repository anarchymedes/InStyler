//
//  VideoPicker.swift
//  InStyler
//
//  Created by Denis Dzyuba on 29/4/2024.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct VideoPicker: UIViewControllerRepresentable {
    
    typealias UIViewControllerType = UIImagePickerController
    typealias Coordinator = VideoPickerCoordinator
    
    @Binding var url: URL?
    @Binding var isShown: Bool
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<VideoPicker>) {
    }
    
    func makeCoordinator() -> VideoPicker.Coordinator {
        return VideoPickerCoordinator(url: $url, sourceType: sourceType, isShown: $isShown)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<VideoPicker>) -> VideoPicker.UIViewControllerType {
        
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoExportPreset = AVAssetExportPresetPassthrough
        picker.delegate = context.coordinator
        return picker
    }
    
}

class VideoPickerCoordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    @Binding var url: URL?
    @Binding var isShown: Bool
    let sourceType: UIImagePickerController.SourceType
    
    init(url: Binding<URL?>, sourceType: UIImagePickerController.SourceType, isShown: Binding<Bool>) {
        _url = url
        _isShown = isShown
        self.sourceType = sourceType
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        let pickedUrl = info[UIImagePickerController.InfoKey.mediaURL] as! URL
        url = pickedUrl
        isShown = false
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        isShown = false
    }
    
}
