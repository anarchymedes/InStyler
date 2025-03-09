//
//  ContentView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 15/11/20.
//

import SwiftUI
import CoreML
import Vision
import Photos
import PhotosUI

struct SelectedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let last = received.file.lastPathComponent // Including extension - and url!.pathExtension is without the leading .
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
            let videoOutputUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent(last))

            if FileManager.default.fileExists(atPath: videoOutputUrl.path()) {
                try FileManager.default.removeItem(at: videoOutputUrl)
            }

            try FileManager.default.copyItem(at: received.file, to: videoOutputUrl)
            
            return Self.init(url: videoOutputUrl)
        }
    }
}

struct ContentView: View {
    
    var style: ImageStyle
    
    @AppStorage("chosenStyle") var chosenStyle: Int?
    @AppStorage("styleChosen") var styleChosen: Bool?

    @State private var showSheet: Bool = false // This is for the image or video slection options
    @State private var showVideoSheet: Bool = false
    @State private var showPhotoOptions: Bool = false
    @State private var showVideoOptions: Bool = false
    @State private var showVideoCapture: Bool = false
    @State private var showASheet: Bool = false // This is for the main sheet
    @State private var showMediaProgress: Bool = false
    @State private var mediaProgressInfo: String = ""
    @State private var image: UIImage?
    @State private var url: URL? = nil
    @State private var imageBeingStylised: Bool = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var cancellationFunc: (()->Void)? = nil
    @State private var ongoingAlertPresenting = false
    @State private var abortNavigation = false
    
    @State private var selectedItem: PhotosPickerItem? = nil
    
    @ObservedObject var observableOrientation: ObservableOrientationWrapper
    
    @State var task: Task<Sendable, Error>? = nil
    
    @State private var initialOrientation = UIDeviceOrientation.unknown
    
    @State private var showShare = false
    @State var targetUrl: URL? = nil // For sharing
    
    @State private var showSettings = false 
    @AppStorage("hiResLocalVideo") private var hiResLocalVideo: Bool = false
    @AppStorage("loResPhoto") private var loResPhoto: Bool = false

    let alertTitle = "Cancel the ongoing stylisation process?"
    
    func secondsToHoursMinutesSeconds(_ seconds: Int) -> (Int, Int, Int) {
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
    
    @MainActor
    private func moveStylisedVideoToPhotos(_ video: URL) async{
        if video.path != "" {
            if FileManager.default.fileExists(atPath: video.path) {
                do {
                    try await PHPhotoLibrary.shared().performChanges({@Sendable in
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
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
#endif

                }
            }
        }
    }
    
    @MainActor
    private func uiCleanup() {
        showMediaProgress = false
        cancellationFunc = nil
        url = nil
        image = nil
    }
    
    //MARK: - Prepare data for sharing
    @MainActor
    func actionSheet() {
        guard image != nil || url != nil else { return }
        if image != nil {
            if let imgdata = image!.pngData() {
                let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
                targetUrl = URL(fileURLWithPath: documentsPath.appendingPathComponent("stylisedPhoto")).appendingPathExtension("png")
                do {
                    if FileManager.default.fileExists(atPath: targetUrl!.path) {
                        try FileManager.default.removeItem(at: targetUrl!)
#if DEBUG
                        print("temp photo removed")
#endif
                    }
                    // Now save the image to a temporary file
                    try imgdata.write(to: targetUrl!, options: .atomic)
                } catch {
#if DEBUG
                    print(error)
#endif
                }
            }
        }
        else if url != nil {
            targetUrl = url
        }

        showVideoSheet = false
        showPhotoOptions = false
        showVideoOptions = false
        showVideoCapture = false

        showShare = true
   }

    //MARK: - Stylising function
    private func stylizeImage() async {
        
        guard let originalSize = image?.size
        else {
            return
        }
        
        guard let buf = image?.toBuffer()
        else {
            return
        }
        
        guard let stylisedBuf = stylizePicture(buf, chosenStyle: chosenStyle, forImages: !loResPhoto) else {
            return
        }
        
        let stylised = UIImage.imageFromCVPixelBuffer(pixelBuffer: stylisedBuf)
        
        DispatchQueue.main.async {
            image = stylised?.resizeTo(size: originalSize)
            
            if (image != nil){
                UIImageWriteToSavedPhotosAlbum(image!, nil, nil, nil)
            }
        }
    }
    
    @MainActor
    func chooseStyleButton()->some View {
        Button("Choose different style") {
            if abortNavigation {
                ongoingAlertPresenting = true
            } else {
                uiCleanup()
                //chosenStyle = -1
                styleChosen = false
            }
        }.padding()
        .modifier(ButtonModifier())
        .padding(.vertical, 36)// Choose Different Style
        .modifier(CancelAlertModifier(showing: $ongoingAlertPresenting, message: alertTitle, yesAction: {
            cancellationFunc?()
            ongoingAlertPresenting = false
            // Whatever it's meant to do
            //chosenStyle = -1
            styleChosen = false
        }, noAction: {
            ongoingAlertPresenting = false
            abortNavigation = true
        }))
    }
    
    //MARK: - The view proper
    var body: some View {
        
        NavigationView {
            
            ZStack {
                VStack {
                    Spacer()
                    VStack{
                        if showMediaProgress {
                            MediaPreviewView(image: $image, url: $url, imageBeingStylised: $imageBeingStylised)
                                .padding(5)
                                .overlay(){
                                    StylisationProgressView(progressInfo: $mediaProgressInfo, cancelAction: { cancellationFunc?() })
                                }
                        }
                        else {
                            MediaPreviewView(image: $image, url: $url, imageBeingStylised: $imageBeingStylised)
                                .padding(5)
                        }

                        // Choose Picture
                        HStack {
                            //MARK: - Choose Picture button
                            Button("Choose Picture") {
                                // open action sheet
                                if abortNavigation {
                                    ongoingAlertPresenting = true
                                } else {
                                    uiCleanup()
                                    self.showSheet = true
                                }
                            }.padding()
                                .modifier(ButtonModifier())
                                .modifier(CancelAlertModifier(showing: $ongoingAlertPresenting, message: alertTitle, yesAction: {
                                    cancellationFunc?()
                                    ongoingAlertPresenting = false
                                    // Whatever it's meant to do
                                    self.showSheet = true
                                }, noAction: {
                                    ongoingAlertPresenting = false
                                    abortNavigation = true
                                }))
                                .actionSheet(isPresented: $showSheet) {
                                    ActionSheet(title: Text("Select Photo"), message: Text("Choose"), buttons: [
                                        .default(Text("Photo Library")) {
                                            // open photo library
                                            self.showASheet = true
                                            self.showVideoCapture = false
                                            self.showVideoOptions = false
                                            self.showPhotoOptions = true
                                            self.sourceType = .photoLibrary
                                        },
                                        .default(Text("Camera")) {
                                            // open camera
                                            self.showASheet = true
                                            self.showVideoCapture = false
                                            self.showPhotoOptions = true
                                            self.sourceType = .camera
                                        },
                                        .cancel()
                                    ])
                                }//Choos Picture
                            
                            Spacer()
                            
                            //MARK: - Choose Video button
                            Button("Choose Video") {
                                if abortNavigation {
                                    ongoingAlertPresenting = true
                                } else {
                                    uiCleanup()
                                    self.showVideoSheet = true
                                }
                            }
                            .padding()
                            .modifier(ButtonModifier())
                            .modifier(CancelAlertModifier(showing: $ongoingAlertPresenting, message: alertTitle, yesAction: {
                                cancellationFunc?()
                                ongoingAlertPresenting = false
                                // Whatever it's meant to do
                                self.showVideoSheet = true
                            }, noAction: {
                                ongoingAlertPresenting = false
                                abortNavigation = true
                            }))
                            .actionSheet(isPresented: $showVideoSheet) {
                                ActionSheet(title: Text("Select Source"), message: Text("Choose"), buttons: [
                                    .default(Text("Video Library")) {
                                        // open photo library
                                        self.showASheet = true
                                        self.showVideoCapture = false
                                        self.showVideoOptions = true
                                        self.showPhotoOptions = false
                                        self.sourceType = .photoLibrary
                                    },
                                    .default(Text("Camera")) {
                                        // open camera
                                        self.showASheet = true
                                        self.showPhotoOptions = false
                                        self.showVideoCapture = true
                                        self.showVideoOptions = false
                                    },
                                    .cancel()
                                ])
                            }
                            
                            if observableOrientation.orientation == .landscapeLeft || observableOrientation.orientation == .landscapeRight {
                                Spacer()
                                // MARK: - Choose Different Style button in landscape
                                chooseStyleButton()
                            }
                        }//:HStack
                        .padding()// Choose Video
                    }// Inner VStack
                    .frame(minWidth: 0, maxWidth: observableOrientation.orientation == .landscapeLeft || observableOrientation.orientation == .landscapeRight ? 640 : 480, minHeight: 0, maxHeight: .infinity, alignment: .center)
                    .background(Color.white.opacity(0.0))

                    if observableOrientation.orientation != .landscapeLeft && observableOrientation.orientation != .landscapeRight {
                        Spacer()
                        
                        HStack{
                            Spacer()
                            // MARK: - Choose Different Style button in portrait
                            chooseStyleButton()
                        }.padding() // HStack
                    }
                }//VStack
                VStack {
                    HStack {
                        Spacer()
                        // MARK: - Settings & Share buttons
                        HStack {
                            Button(action: {
                                showSettings = true
                            }, label: {
                                Label("Settings", systemImage: "gear")
                            })
                            .padding()
                            .offset(y:30)
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                            .sheet(isPresented: $showSettings, content: {
                                SettingsView()
                            })

                            Spacer()
                            
                            Button(action: {
                                actionSheet()
                            }, label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            })
                            .padding()
                            .disabled((image == nil && url == nil) || showMediaProgress || imageBeingStylised)
                            .foregroundColor((image == nil && url == nil) ? .gray : .white)
                            .offset(y:30)
                            .shadow(radius: 5)
                            .sheet(isPresented: $showShare, content: {
                                ActivityViewController(url: self.$targetUrl, excludedActivityTypes: nil)
                            })
                        }
                    }
                    Spacer()
                }
            }//ZStack
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(.all, edges: .all)
            .navigationBarTitle("Style Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }//NavigationView
        .navigationViewStyle(StackNavigationViewStyle())
        .ignoresSafeArea(.all, edges:.all)
        .sheet(isPresented: $showASheet) {
            if showPhotoOptions {
                if (self.sourceType == .camera)
                {
                    // MARK: - Show photo capture
                    PhotoCameraView(style: style, isPresented: $showASheet, selectedImage: $image, observableOrientation: observableOrientation)
                }
                else {
                    // MARK: - Show photo picker
                    PhotosPicker("Images", selection: $selectedItem, matching: .images)
                        .photosPickerStyle(.inline)
                        .modifier(ResetTrigger(isShown: $showVideoCapture))
                        .modifier(ResetTrigger(isShown: $showVideoOptions))
                        .onAppear {
                            uiCleanup()
                        }
                        .onDisappear {
                            Task {
                                if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                                    image = UIImage(data: data)
                                    if image != nil {
                                        DispatchQueue.main.async {
                                            imageBeingStylised = true
                                        }
                                        await stylizeImage()
                                        DispatchQueue.main.async {
                                            imageBeingStylised = false
                                        }
                                    }
                                }
                            }
                        }
                }
            }
            else if showVideoOptions {
                // MARK: - Show video picker
                PhotosPicker("Videos", selection: $selectedItem,  matching: .videos)
                    .photosPickerStyle(.inline)
                    .modifier(ResetTrigger(isShown: $showVideoCapture))
                    .modifier(ResetTrigger(isShown: $showPhotoOptions))
                    .onAppear {
                        uiCleanup()
                    }
                    .onDisappear() {
                        // MARK: - A video was chosen
                        Task {
                            if let movie = try? await selectedItem?.loadTransferable(type: SelectedMovie.self) {
                                url = movie.url
                                if url != nil {
                                    abortNavigation = true
                                    cancellationFunc = {
                                        task?.cancel()
                                        showMediaProgress = false
                                        uiCleanup()
                                    }
                                    guard let url = self.url else {
                                        return 0 // Weird: see below
                                    }
    #if DEBUG
                                    print(url.absoluteString)
    #endif
                                    let styliser = FileStyliser(for: url, model: pickModel(chosenStyle: chosenStyle, forImages: hiResLocalVideo))
                                    
                                    await styliser.loadTracks()
                                    //MARK: - Update the progress info
                                    showMediaProgress = true
                                    await styliser.stylise(reportOnEvery: 30) {(frame, secs, correct, error) in
                                        Task{@MainActor in
                                            if (error != "")
                                            {
                                                print(error)
                                                return
                                            }

                                            let (hours, minutes, seconds) = secondsToHoursMinutesSeconds(Int(secs.rounded()))

                                            let update = (correct ? "Stylised" : "Copied" ) + " \(String(format: "%02d", hours)):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds)) (\(frame) frames)."

                                            mediaProgressInfo = update
                                        }
                                    }
                                    Task {@MainActor in
                                        showMediaProgress = false
                                        try FileManager.default.removeItem(at: url)
    #if DEBUG
                                        print("original removed")
    #endif
                                        if let task = task, task.isCancelled {
                                            try FileManager.default.removeItem(at: styliser.destinationURL)
                                        }
                                        else {
                                            await moveStylisedVideoToPhotos(styliser.destinationURL)
                                            self.url = styliser.destinationFileExists ? styliser.destinationURL : nil
                                        }
                                        abortNavigation = false
                                        cancellationFunc = nil
                                        task = nil
                                    }
                                }
                            }
                            return 0 // This is WEIRD, and shouldn't benecessary
                        }
                    }
            
            }
            else if showVideoCapture {
                // MARK: - Show video capture UI
                VideoRecordingView(style: style, isShowing: $showASheet, observableOrientation: observableOrientation)
                    .onAppear(){
                        // Make sure there is nothing when we choose nothing
                        uiCleanup()
                        do {
                            if CameraController.instance.destinationFileExists {
                                try FileManager.default.removeItem(at: CameraController.instance.destinationURL)
        #if DEBUG
                                print("temp media removed")
        #endif
                            }
                        } catch {
        #if DEBUG
                            print(error)
        #endif
                        }
                    }
                    .onDisappear(){
                        // Make sure there is something if we've chosen something
                        url = CameraController.instance.destinationFileExists ? CameraController.instance.destinationURL : nil
                    }
                    .edgesIgnoringSafeArea(.top)
                    .modifier(ResetTrigger(isShown: $showPhotoOptions))
                    .modifier(ResetTrigger(isShown: $showVideoOptions))
            }
        }
        .onRotate(){ newRotation in
            observableOrientation.orientation = newRotation
            initialOrientation = newRotation
        }
    }
}

//MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(style: styles[0], observableOrientation: ObservableOrientationWrapper())
    }
}
