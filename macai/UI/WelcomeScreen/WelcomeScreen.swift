//
//  WelcomeScreen.swift
//  macai
//
//  Created by Renat Notfullin on 25.03.2023.
//

import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var gptTokenIsPresent: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    
    
    var body: some View {
        GeometryReader { geometry in

            ZStack {
                // if new user, show beautiful welcome particles
                if chatsCount == 0 {
                    SceneKitParticlesView()
                        .edgesIgnoringSafeArea(.all)
                }

                // if gptToken is not set, show button to open settings
                if !gptTokenIsPresent {

                    VStack {
                        WelcomeIcon()

                        VStack {
                            Text("Welcome to macai!").font(.title)
                            Text("To get started, please set ChatGPT API token in settings")
                            Button("Open Settings") {
                                openPreferencesView()
                            }
                        }
                        .padding(.bottom, 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                }
                else {
                    //
                    VStack {
                        WelcomeIcon()

                        VStack {
                            if chatsCount == 0 {
                                Text("No chats were created yet. Create new one?")
                                Button("Create new chat") {
                                    newChat()
                                }
                            }
                            else {
                                Text("Select chat to get started, or create new one")
                            }
                        }
                        .padding(.bottom, 60)

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                }

            }

        }
    }
}

struct WelcomeIcon: View {
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        let dragGesture = DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, transaction in
                state = value.translation
            }

        Image("WelcomePic")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 2688, maxHeight: 1792)
            .shadow(color: Color(red: 65/255, green: 50/255, blue: 145/255), radius: 60, x: -10, y: 10)
            .shadow(color: Color(red: 51/255, green: 129/255, blue: 191/255), radius: 15, x: 10, y: 15)
            .shadow(color: Color(red: 81/255, green: 195/255, blue: 228/255), radius: 120, x: 0, y: 20)
            .rotation3DEffect(
                Angle(degrees: Double(dragOffset.width / 60)),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .rotation3DEffect(
                Angle(degrees: Double(-dragOffset.height / 60)),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .gesture(dragGesture)
            .padding(30)
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(chatsCount: 0, gptTokenIsPresent: true, openPreferencesView: {}, newChat: {})
    }
}
