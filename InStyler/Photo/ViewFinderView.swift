//
//  ViewFinderView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/3/2025.
//  Based on the code from this Apple tutorial:
//  doc://com.apple.documentation/tutorials/sample-apps/CapturingPhotos-BrowsePhotos
//
import SwiftUI

struct ViewfinderView: View {
    @Binding var image: Image?
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

struct ViewfinderView_Previews: PreviewProvider {
    static var previews: some View {
        ViewfinderView(image: .constant(Image(systemName: "pencil")))
    }
}
