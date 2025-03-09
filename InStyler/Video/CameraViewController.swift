//
//  CameraView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 29/11/20.
//

import UIKit
import SwiftUI
//import AVFoundation

final class CameraViewController: UIViewController {
    let cameraController = CameraController.instance
    var previewView: UIView!
    
    private var orientation: UIDeviceOrientation = .unknown
    private var originalOrientation: UIDeviceOrientation = .unknown

    override func viewDidLoad() {
        originalOrientation = ObservableOrientationWrapper.getOrientation()
        
        cameraController.didOutputNewImage = {(img: UIImage) -> Void in
            DispatchQueue.main.async{
                self.previewView = UIImageView(image: img)
                
                // The code below is to create the best possible match between the preview and the recorded content
                if self.originalOrientation == .portrait {
                    if self.orientation == .landscapeLeft {
                        self.previewView.transform = CGAffineTransformMakeRotation(-Double.pi/2);
                    }
                    else if self.orientation == .landscapeRight {
                        self.previewView.transform = CGAffineTransformMakeRotation(Double.pi/2);
                    }
                    else if self.orientation != .portrait && self.orientation != .unknown {
                        self.previewView.transform = CGAffineTransformMakeRotation(Double.pi);
                    }
                }
                else if self.originalOrientation == .landscapeLeft {
                    if self.orientation == .portrait {
                        self.previewView.transform = CGAffineTransformMakeRotation(Double.pi/2);
                    }
                    else if self.orientation == .landscapeRight {
                        self.previewView.transform = CGAffineTransformMakeRotation(Double.pi);
                    }
                    else if self.orientation != .landscapeLeft && self.orientation != .unknown {
                        self.previewView.transform = CGAffineTransformMakeRotation(-Double.pi/2);
                    }
                }

                if self.orientation == .portrait || self.orientation == .portraitUpsideDown {
                    if self.originalOrientation == .portrait || self.originalOrientation == .portraitUpsideDown {
                        self.previewView.contentMode = UIView.ContentMode.scaleAspectFit
                    }
                    else {
                        self.previewView.contentMode = UIView.ContentMode.scaleAspectFill
                    }
                }
                else {
                    if self.originalOrientation == .landscapeLeft || self.originalOrientation == .landscapeRight {
                        self.previewView.contentMode = UIView.ContentMode.scaleAspectFit
                    }
                    else {
                        self.previewView.contentMode = UIView.ContentMode.scaleAspectFill
                    }
                }
                self.previewView.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
                self.previewView.translatesAutoresizingMaskIntoConstraints = true
                
                self.view = self.previewView
            }
        }
    }
    
    func startRecording() {
        cameraController.startRecording()
    }
    
    func stopRecording() {
        cameraController.stopRecording()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        cameraController.prepare {(error) in
            if let error = error {
                print(error)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self,
                                      selector: #selector(orientationDidChange),
                    name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        cameraController.unprepare()
    }
    
    @objc func orientationDidChange(_ notification: Notification) {
        // Handle the orientation change
        // Useful for more specific reactions to orientation changes
        orientation = ObservableOrientationWrapper.getOrientation()
    }
}

struct CameraViewRep : UIViewControllerRepresentable{
    public typealias UIViewControllerType = CameraViewController
    
    public func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
    }
}
