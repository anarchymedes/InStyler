//
//  StylisationProgressView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 3/5/2024.
//

import SwiftUI

struct StylisationProgressView: View {
    @Binding var progressInfo: String
    var cancelAction: ()->Void
    
    @AppStorage("chosenStyle") var chosenStyle: Int?

    func updateProgress(with info: String) {
        progressInfo = info
    }
    
    var body: some View {
        VStack {
            Text(progressInfo)
                .padding(.horizontal)
            Button("Cancel", action: {
                cancelAction()
            }).font(.title2)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10.0).fill(.ultraThinMaterial))
    }
}

#Preview {
    StylisationProgressView(progressInfo: .constant("Finished 00:00 (до хуя frames)"), cancelAction: {})
}
