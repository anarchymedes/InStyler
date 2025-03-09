//
//  ChooseStyleView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 16/11/20.
//

import SwiftUI

struct ChooseStyleView: View {
    @AppStorage("chosenStyle") var chosenStyle: Int?
    @AppStorage("styleChosen") var styleChosen: Bool?
    
    @State var idx: UUID
    
    @ObservedObject var observableOrientation: ObservableOrientationWrapper
    
    func buildTabs()->some View {
        return TabView(selection: $idx) {
            ForEach(styles[0..<styles.count]){item in
                StyleCardView(style: item, observableOrientation: observableOrientation).tag(item.id)
            }//Loop
        }//TabView
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea(.all, edges: .all)
        .tabViewStyle(PageTabViewStyle())
        .padding(.vertical, 20)
    }
    
    var body: some View {
        if styleChosen != nil, let chosenStyle = chosenStyle {
            if chosenStyle >= 0 {
                buildTabs()
                    .onAppear(){
                        if chosenStyle >= 0 && chosenStyle < styles.count {
                            idx = styles[chosenStyle].id
                        }
                        else {
                            idx = styles[0].id
                        }
                    }
            }
            else {
                buildTabs()
            }
        }
        else {
            buildTabs()
        }
    }
}

struct ChooseStyleView_Previews: PreviewProvider {
    static var previews: some View {
        ChooseStyleView(idx: styles[0].id, observableOrientation: ObservableOrientationWrapper())
    }
}
