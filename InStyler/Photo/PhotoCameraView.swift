//
//  PhotoCameraView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/3/2025.
//  Based on the code from this Apple tutorial:
//  doc://com.apple.documentation/tutorials/sample-apps/CapturingPhotos-BrowsePhotos
//
import SwiftUI

struct PhotoCameraView: View, @preconcurrency CaptureCompletionDelegate {
    var style: ImageStyle
    
    @StateObject private var model = PhotoDataModel()

    @Binding var isPresented: Bool
    @Binding var selectedImage: UIImage?
    @ObservedObject var observableOrientation: ObservableOrientationWrapper
    private static let barHeightFactor = 0.15
    
    func setImageAndClose(_ image: UIImage?, _ presented: Bool) {
        isPresented = presented
        selectedImage = image
    }

    var body: some View {
        NavigationStack {
            Group {
                if observableOrientation.orientation.isLandscape {
                    GeometryReader { geometry in
                        ViewfinderView(image:  $model.viewfinderImage )
                            .overlay(alignment: .leading) {
                                Color.black
                                    .opacity(0.75)
                                    .frame(width: geometry.size.width * Self.barHeightFactor)
                                    .frame(maxHeight: .infinity)
                            }
                            .overlay(alignment: .trailing) {
                                buttonsView()
                                    .frame(width: geometry.size.width * Self.barHeightFactor)
                                    .background(.black.opacity(0.75))
                            }
                            .overlay(alignment: .center)  {
                                Color.clear
                                    .frame(width: geometry.size.width * (1 - (Self.barHeightFactor * 2)))
                                    .frame(maxHeight: .infinity)
                                    .accessibilityElement()
                                    .accessibilityLabel("View Finder")
                                    .accessibilityAddTraits([.isImage])
                            }
                            .background(.black)
                        }
                        .task {
                            await model.camera.start()
                            await model.loadPhotos()
                        }
                        .navigationTitle("Camera")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarHidden(true)
                        .ignoresSafeArea()
                        .statusBar(hidden: true)
                    }
                else {
                    GeometryReader { geometry in
                        ViewfinderView(image:  $model.viewfinderImage )
                            .overlay(alignment: .bottom) {
                                Color.black
                                    .opacity(0.75)
                                    .frame(height: geometry.size.height * Self.barHeightFactor)
                                    .frame(maxWidth: .infinity)
                            }
                            .overlay(alignment: .bottom) {
                                buttonsView()
                                    .frame(height: geometry.size.height * Self.barHeightFactor)
                                    .frame(maxWidth: .infinity)
                                    .background(.black.opacity(0.75))
                            }
                            .overlay(alignment: .center)  {
                                Color.clear
                                    .frame(height: geometry.size.height * (1 - (Self.barHeightFactor * 2)))
                                    .accessibilityElement()
                                    .accessibilityLabel("View Finder")
                                    .accessibilityAddTraits([.isImage])
                            }
                            .background(.black)
                    }
                    .task {
                        await model.camera.start()
                        await model.loadPhotos()
                    }
                    .navigationTitle("Camera")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarHidden(true)
                    .ignoresSafeArea()
                    .statusBar(hidden: true)
                }
            }
        }
        .onRotate { newOrientation in
            observableOrientation.orientation = newOrientation }
        .onAppear {
            model.completionDelegate = self
        }
    }
    
    private func buttonsView() -> some View {
        Group {
            if observableOrientation.orientation.isLandscape {
                HStack {
                    Spacer()
                    VStack(spacing: 72) {
                        
                        Button {
                            model.camera.switchCaptureDevice()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical)
                        }

                        Button {
                            model.camera.takePhoto()
                            //TODO: update the app's image preview, and close the sheet
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                    .frame(width: 56, height: 56)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .padding(.horizontal, 32)
                        }
                        
                        Button(action: {
                            CameraController.instance.showError = false
                            isPresented = false
                        }, label: {
                            Image(systemName: "arrowshape.turn.up.backward")
                                .font(.largeTitle)
                                .frame(minWidth: 45)
                                .padding(.horizontal)
                                .padding(7.5)
                        })
                        .modifier(ButtonModifier())
                        .padding(.vertical, 32)
                        
                    }//VSTACK
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .padding(.vertical)
                    .padding(.horizontal, 1.5)
                    .frame(maxHeight: .infinity)
                    .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .leading, endPoint: .trailing).opacity(0.75))
                }
            }
            else {
                VStack {
                    Spacer()
                    HStack(spacing: 60) {
                        
                        Button {
                            model.camera.switchCaptureDevice()
                        } label: {
                            Label("Switch Camera", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                        }
                        
                        Button {
                            model.camera.takePhoto()
                            //TODO: update the app's image preview, and close the sheet
                        } label: {
                            Label {
                                Text("Take Photo")
                            } icon: {
                                ZStack {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 3)
                                        .frame(width: 56, height: 56)
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }
                        
                        Button(action: {
                            CameraController.instance.showError = false
                            isPresented = false
                        }, label: {
                            Image(systemName: "arrowshape.turn.up.backward")
                                .font(.largeTitle)
                                .frame(minWidth: 45)
                                .padding(.horizontal)
                                .padding(7.5)
                        })
                        .modifier(ButtonModifier())
                        .padding(.trailing, 24)
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .padding(.vertical, 32)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .top, endPoint: .bottom).opacity(0.75))
                }
            }
        }
    }
}

struct PhotoCameraView_Previews : PreviewProvider {
    @State static var selectedPreviewImage: UIImage? = nil
    static var previews: some View {
        PhotoCameraView(style: styles[0], isPresented: .constant(true), selectedImage: $selectedPreviewImage, observableOrientation: ObservableOrientationWrapper())
    }
}
