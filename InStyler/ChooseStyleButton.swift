//
//  ChooseStyleButton.swift
//  InStyler
//
//  Created by Denis Dzyuba on 16/11/20.
//

import SwiftUI

struct ChooseStyleButton: View {
    
    @AppStorage("chosenStyle") var chosenStyle: Int?
    @AppStorage("styleChosen") var styleChosen: Bool?

    var style: ImageStyle
    
    var body: some View {
        Button(action: {
            chosenStyle = style.modelSelector
            styleChosen = true
        }){
            HStack(spacing: 8) {
              Text("Choose this style")
              
              Image(systemName: "arrow.right.circle")
                .imageScale(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
              Capsule().strokeBorder(Color.white, lineWidth: 1.25)
            )
        }// Button
        .accentColor(Color.white)
    }
}

struct ChooseStyleButton_Previews: PreviewProvider {
    static var previews: some View {
        ChooseStyleButton(style: styles[0])
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
    }
}
