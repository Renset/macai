//
//  MessageInputView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import OmenTextField
import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    var onEnter: () -> Void
    @State var frontReturnKeyType = OmenTextField.ReturnKeyType.next
    @State var isFocused: Focus?
    @State var dynamicHeight: CGFloat = 32.0

    enum Focus {
        case focused, notFocused
    }

    var body: some View {
        ZStack {
        // Hidden text view for dynamic height calculation
        Text(text)
            .font(.body)
            .lineLimit(6)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        dynamicHeight = min(max(geometry.size.height, 16), 96) + 16
                    }
                    .onChange(of: text) { _ in
                        dynamicHeight = min(max(geometry.size.height, 16), 96) + 16
                    }
            })
            .padding(8)
            .hidden()
            
            ScrollView {
                VStack {
                    OmenTextField(
                        "Type your message here",
                        text: $text,
                        isFocused: $isFocused.equalTo(.focused),
                        returnKeyType: frontReturnKeyType,
                        onCommit: {
                            onEnter()
                        }
                    )
                    
                }
                .padding(8)
            }
            .frame(height: dynamicHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isFocused == .focused ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5),
                        lineWidth: isFocused == .focused ? 3 : 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            )
            .onTapGesture {
                isFocused = .focused
            }
        }
        
    }
}

extension Binding {
    func equalTo<A: Equatable>(_ value: A) -> Binding<Bool> where Value == A? {
        Binding<Bool> {
            wrappedValue == value
        } set: {
            if $0 {
                wrappedValue = value
            }
            else if wrappedValue == value {
                wrappedValue = nil
            }
        }
    }
}

struct MessageInputView_Previews: PreviewProvider {
    static var previews: some View {
        MessageInputView(text: .constant("Some input message"), onEnter: {})
    }
}
