//
//  StyleModel.swift
//  InStyler
//
//  Created by Denis Dzyuba on 16/11/20.
//

import Foundation
import SwiftUI
import CoreML

struct ImageStyle: Identifiable {
    var id = UUID()
    var title: String
    var image: String
    var gradientColors: [Color]
    var description: String
    var modelSelector: Int
}


