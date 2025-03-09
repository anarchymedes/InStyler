//
//  ActivityVieewController.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/5/2024.
//

import Foundation
import SwiftUI
import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    @Binding var url: URL?
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        
        let controller = UIActivityViewController(activityItems: url != nil ? [url!] : [],
                                                  applicationActivities: nil)
        
        controller.excludedActivityTypes = excludedActivityTypes
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}
