//
//  SettingsView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 14/5/2024.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("hiResLocalVideo") private var hiResLocalVideo: Bool?
    @AppStorage("loResPhoto") private var loResPhoto: Bool?

    @State private var currentHiResLocalVideos = false
    @State private var currentLoResPhotos = false

    var body: some View {
        Form{
            Section(footer: Text("The models used to stylise images are more detailed than the ones used to preview and capture stylised live videos; however, they may introduce some flickering between frames, as they treat every frame as an individual image. They are also **considerably** slower. NOTE: this setting applies **only** to the library videos, **not** the live capture.")){
                Toggle("Stylise library videos as images", isOn: $currentHiResLocalVideos)
            }
            Section(footer: Text("Due to the higher level of detail of the image stylisation models, they may, depending on the style, sometimes introduce undesirable artefacts, making the lower-detail real-time video model a better choice. NOTE: this setting applies to both the captured photos **and** the library images.")){
                Toggle("Stylise pictures as videos", isOn: $currentLoResPhotos)
            }
        }
        .onAppear {
            currentHiResLocalVideos = hiResLocalVideo ?? false
            currentLoResPhotos = loResPhoto ?? false
        }
        .onDisappear{
            hiResLocalVideo = currentHiResLocalVideos
            loResPhoto = currentLoResPhotos
        }
    }
}

#Preview {
    SettingsView()
}
