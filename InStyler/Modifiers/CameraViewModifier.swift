//
//  CameraViewModifier.swift
//  InStyler
//
//  Created by Denis Dzyuba on 29/11/20.
//

import SwiftUI

struct ResetTrigger: ViewModifier{
    @Binding var isShown: Bool
    
    func body(content: Content) -> some View{
        isShown = false
        return content
    }
}
