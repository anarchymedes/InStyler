//
//  MediaPreviewView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 1/5/2024.
//

import SwiftUI
import AVKit

struct MediaPreviewView: View {
    @Binding var image: UIImage?
    @Binding var url: URL?
    @Binding var imageBeingStylised: Bool
    
    var body: some View {
        ZStack {
            if url != nil {
                EmptyView()
            }
            else {
                ZStack {
                    Image(uiImage: image ?? UIImage(named: "placeholder")!)
                        .resizable()
                        .scaledToFit()
                    .opacity(image == nil ? 0.36 : 1.0)
                    if imageBeingStylised {
                        ActivityIndicator(isAnimating: .constant(true), style: .large)
                    }
                }
            }
            if let url = url {
                VideoPlayer(player: AVPlayer(url: url))
                    .scaledToFit()
                    .background(){
                        Color(.clear).opacity(0)
                    }
            }
        }
    }
}

#Preview {
    MediaPreviewView(image: .constant(nil), url: .constant(nil), imageBeingStylised: .constant(true))
}
