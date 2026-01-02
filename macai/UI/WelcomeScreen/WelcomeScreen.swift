//
//  WelcomeScreen.swift
//  macai
//
//  Created by Renat Notfullin on 25.03.2023.
//

import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    var customUrl: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void

    var body: some View {
        #if os(iOS)
        let iconPadding: CGFloat = 32
        let bottomPadding: CGFloat = 24
        #else
        let iconPadding: CGFloat = 64
        let bottomPadding: CGFloat = 60
        #endif

        GeometryReader { geometry in

            ZStack {
                if chatsCount == 0 && !apiServiceIsPresent {
                    #if os(macOS)
                    SceneKitParticlesView()
                        .edgesIgnoringSafeArea(.all)
                    #endif
                }

                VStack {
                    WelcomeIcon()
                        .padding(iconPadding)

                    VStack {
                        Text("Welcome to macai!").font(.title)
                        if !apiServiceIsPresent {
                            Text("To get started, please add at least one API Service in the settings")
                            #if os(macOS)
                            if #available(macOS 14.0, *) {
                                SettingsLink {
                                    Text("Open Settings")
                                }
                            }
                            else {
                                Button("Open Settings") {
                                    openPreferencesView()
                                }
                            }
                            #else
                            Button("Open Settings") {
                                openPreferencesView()
                            }
                            #endif
                        }
                        else {
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
                    }
                    .padding(.bottom, bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
            .background(Color(.systemBackground).ignoresSafeArea())
            #endif

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

            .shadow(color: Color(red: 0.86, green: 0.46, blue: 0.00), radius: 60, x: -10, y: 10)
            .shadow(color: Color(red: 0.98, green: 0.86, blue: 0.29), radius: 30, x: 10, y: 15)
            .shadow(color: Color(red: 1.00, green: 0.67, blue: 0.00), radius: 60, x: 18, y: -10)
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
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(chatsCount: 0, apiServiceIsPresent: true, customUrl: false, openPreferencesView: {}, newChat: {})
    }
}
