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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                }
                else {
                    //
                    VStack {
                        WelcomeIcon()

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

        Image("WelcomeIcon")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 256, maxHeight: 256)
            .shadow(color: Color(red: 1, green: 0.853, blue: 0.281), radius: 15, x: -10, y: 10)
            .shadow(color: Color(red: 1, green: 0.593, blue: 0.261), radius: 15, x: 10, y: 15)
            .shadow(color: Color(red: 0.9, green: 0.5, blue: 0.0), radius: 38, x: 0, y: 20)
            .rotation3DEffect(
                Angle(degrees: Double(dragOffset.width / 20)),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .rotation3DEffect(
                Angle(degrees: Double(-dragOffset.height / 20)),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .gesture(dragGesture)
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(chatsCount: 0, gptTokenIsPresent: true, openPreferencesView: {}, newChat: {})
    }
}
