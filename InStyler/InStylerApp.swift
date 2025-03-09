//
//  InStylerApp.swift
//  InStyler
//
//  Created by Denis Dzyuba on 15/11/20.
//

import UIKit
import SwiftUI

@main
struct InStylerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("chosenStyle") var chosenStyle: Int = -1
    @AppStorage("styleChosen") var styleChosen: Bool = false
    
    @StateObject var observableOrientation: ObservableOrientationWrapper = ObservableOrientationWrapper()
    
    var body: some Scene {
        WindowGroup {
            if (!styleChosen){
                ChooseStyleView(idx: styles[(chosenStyle >= 0) ? chosenStyle : 0].id, observableOrientation: observableOrientation)
            } else {
                ContentView(style: (chosenStyle >= 0) ? styles[chosenStyle] : styles[0], observableOrientation: observableOrientation)
            }
        }
    }
}

@MainActor class ObservableOrientationWrapper: ObservableObject {
    public static func getOrientation()->UIDeviceOrientation {
        if UIDevice.current.orientation == .unknown {
            if let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation {
                switch orientation {
                case .portrait:
                    return .portrait
                case .landscapeLeft:
                    return.landscapeLeft
                case .landscapeRight:
                    return.landscapeRight
                case .portraitUpsideDown:
                    return .portraitUpsideDown
                case .unknown:
                    return .portrait
                default:
                    return .portrait
                }
            }
        }
        return UIDevice.current.orientation
    }
    @Published var orientation: UIDeviceOrientation = getOrientation()
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
        
    static var orientationLock = UIInterfaceOrientationMask.all //By default you want all your views to rotate freely
    static var noRotation: Bool = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.noRotation ? UIInterfaceOrientationMask.portrait : AppDelegate.orientationLock
    }
}

extension UIApplication {
    
    // MARK: No shame!
    
    static func TopPresentedViewController() -> UIViewController? {
        
        guard let rootViewController = UIApplication.shared
                .connectedScenes.lazy
                .compactMap({ $0.activationState == .foregroundActive ? ($0 as? UIWindowScene) : nil })
                .first(where: { $0.keyWindow != nil })?
                .keyWindow?
                .rootViewController
        else {
            return nil
        }
        
        var topController = rootViewController
        
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        
        return topController
        
    }
    
}
