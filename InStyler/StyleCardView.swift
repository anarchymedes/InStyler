//
//  StyleCardView.swift
//  InStyler
//
//  Created by Denis Dzyuba on 16/11/20.
//

import SwiftUI

struct StyleCardView: View {
    
    var style: ImageStyle
    @State var isAnimating: Bool = false
    @AppStorage("chosenStyle") var chosenStyle: Int?
    @ObservedObject var observableOrientation: ObservableOrientationWrapper
    
    var body: some View {
        Group{
            if observableOrientation.orientation == .landscapeLeft || observableOrientation.orientation == .landscapeRight {
                VStack(spacing: 15) {
                    HStack(spacing:10){
                        //Thumbnail
                        Image(style.image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(10)
                            .frame(minWidth: 0, idealWidth: 320, maxWidth: 640, minHeight: 0, idealHeight: 186, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                            .padding(.leading)
                            .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.5), radius: 8, x: 6, y: 8)
                            .scaleEffect(isAnimating ? 1.0 : 0.6)
                        VStack(spacing: 15) {
                            //Title
                            Text(style.title)
                                .foregroundColor(Color.white)
                                .font(.largeTitle)
                                .fontWeight(.heavy)
                                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.5), radius: 2, x: 2, y: 2)
                            //Descrtiption
                            Text(style.description)
                                .foregroundColor(Color.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: 640)
                        }
                    }
                    //Choose This Style Button
                    ChooseStyleButton(style: style)
                        .padding(.vertical, 36)
                }
            }
            else {
                VStack(spacing: 40){
                    //Thumbnail
                    Image(style.image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                        .frame(minWidth: 0, idealWidth: 320, maxWidth: 640, minHeight: 0, idealHeight: 186, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.5), radius: 8, x: 6, y: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.6)
                    //Title
                    Text(style.title)
                        .foregroundColor(Color.white)
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.5), radius: 2, x: 2, y: 2)
                    //Descrtiption
                    Text(style.description)
                        .foregroundColor(Color.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: 640)
                    //Choose This Style Button
                    ChooseStyleButton(style: style)
                        .padding(.vertical, 36)
                }//VStack
            }
        }//ZStack
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .background(LinearGradient(gradient: Gradient(colors: style.gradientColors), startPoint: .top, endPoint: .bottom))
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .onAppear {
            //chosenStyle = style.modelSelector
          withAnimation(.easeOut(duration: 0.5)) {
            isAnimating = true
          }
        }
        .onRotate(){ newOrientation in
            observableOrientation.orientation = newOrientation
        }
    }
}

struct StyleCardView_Previews: PreviewProvider {
    static var previews: some View {
        StyleCardView(style: styles[0], observableOrientation: ObservableOrientationWrapper())
    }
}
