//
//  UIButtonModifier.swift
//  InStyler
//
//  Created by Denis Dzyuba on 29/11/20.
//

import SwiftUI

struct ButtonModifier: ViewModifier{
    func body(content: Content) -> some View{
        content
            .foregroundColor(Color.white)
            .background(
              Capsule().strokeBorder(Color.white, lineWidth: 1.25)
            )
            .cornerRadius(10)
    }
}
