//
//  ErrorView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 1/5/2024.
//

import SwiftUI

struct ErrorView: View {
    @State var message: String
    var action: ()->Void
    
    var body: some View {
        VStack {
            Text(message)
                .padding(.horizontal)
            Button("Ok", action: {
                action()
            }).font(.title2)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10.0).fill(.red.opacity(0.25)))
    }
}

#Preview {
    ErrorView(message: "Just when you think you're f...ing them, they're f...ing you!", action: {})
}
