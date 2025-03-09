//
//  VideoRecordingView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 6/12/20.
//

import SwiftUI

struct VideoRecordingView: View {
    
    var style: ImageStyle
    @Binding var isShowing: Bool
    
    @State var startRecording: Bool = false
    @ObservedObject var observableOrientation: ObservableOrientationWrapper
    @State private var isErrorShowing: Bool = false
    
    let preview = CameraViewRep()
    let vc = CameraViewController()
    let ourDelegate = ErrorDelegate()
    
    private func updateErrorShowing(_ showing: Bool) {
        isErrorShowing = showing
    }
    
    private func switchCamera() {
        CameraController.instance.useFront.toggle()
        CameraController.instance.prepare(){(error) in
            if let error = error {
                print(error)
            }
        }
    }
    
    var body: some View {
        ourDelegate.updateIndicator = updateErrorShowing
        return ZStack {
            preview
            Group {
                if observableOrientation.orientation.isLandscape {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            VStack {
                                Button(action: {
                                    switchCamera()
                                }, label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.white)
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                
                                Spacer()
                                
                                Button(action: {
                                    CameraController.instance.showError = false
                                    isErrorShowing = false
                                    
                                    self.startRecording.toggle()
                                    self.startRecording ? vc.startRecording() : vc.stopRecording()
                                }, label: {
                                    Image(systemName: startRecording ? "stop.fill" : "record.circle")
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                .modifier(ButtonModifier())
                                
                                Spacer()
                                
                                Button(action: {
                                    CameraController.instance.showError = false
                                    isErrorShowing = false
                                    if startRecording {
                                        vc.stopRecording()
                                    }
                                    self.startRecording = false
                                    isShowing = false
                                }, label: {
                                    Image(systemName: "arrowshape.turn.up.backward")
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                .modifier(ButtonModifier())
                            }
                            .padding(.vertical)
                            .padding(.horizontal, 1.5)
                        }
                        .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .leading, endPoint: .trailing).opacity(0.75))
                    }
                }
                else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack {
                                Button(action: {
                                    switchCamera()
                                }, label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.white)
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                
                                Spacer()
                                
                                Button(action: {
                                    self.startRecording.toggle()
                                    self.startRecording ? vc.startRecording() : vc.stopRecording()
                                }, label: {
                                    Image(systemName: startRecording ? "stop.fill" : "record.circle")
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                .modifier(ButtonModifier())
                                
                                Button(action: {
                                    if startRecording {
                                        vc.stopRecording()
                                    }
                                    self.startRecording = false
                                    isShowing = false
                                }, label: {
                                    Image(systemName: "arrowshape.turn.up.backward")
                                        .font(.largeTitle)
                                        .frame(minWidth: 45)
                                        .padding(.horizontal)
                                        .padding(7.5)
                                })
                                .modifier(ButtonModifier())
                            }
                            .padding()
                        }
                        .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .top, endPoint: .bottom).opacity(0.75))
                    }
                }
            }
            if isErrorShowing {
                ErrorView(message: "Unfortunately, the workload proved too much for this device: your video got corrupted and will not be saved. Please try again.", action: {
                    CameraController.instance.showError = false
                    self.startRecording = false
                    vc.stopRecording()
                    isErrorShowing = false
                })
            }
        }.onRotate { newOrientation in
            observableOrientation.orientation = newOrientation }
        .onAppear(){
            CameraController.instance.uiDelegate = ourDelegate
        }
        .onDisappear(){
            CameraController.instance.uiDelegate = nil
        }
    }
}

class ErrorDelegate: CameraControllerUIDelegate {
    var updateIndicator: ((Bool)->Void)? = nil
    
    func inErrorState(_ errorState: Bool) {
        updateIndicator?(errorState)
    }
}

struct VideoRecordingView_Previews: PreviewProvider {
    static var previews: some View {
        VideoRecordingView(style: styles[0], isShowing: .constant(true), observableOrientation: ObservableOrientationWrapper())
    }
}
