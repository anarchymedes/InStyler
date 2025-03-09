//
//  CancelAlertModifier.swift
//  InStyler
//
//  Created by Denis Dzyuba on 4/5/2024.
//

import SwiftUI

struct CancelAlertModifier: ViewModifier {
    @Binding var showing: Bool
    var message: String
    var yesAction: ()->Void
    var noAction: ()->Void
    
    func body(content: Content) -> some View{
        content
            .alert(message, isPresented: $showing){
                Button("Yes", action: {
                    yesAction()
                })
                Button("No", action: {
                    noAction()
                })
            }
    }
}
