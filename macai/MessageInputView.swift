//
//  MessageInputView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import SwiftUI
import OmenTextField

struct MessageInputView: View {
    @Binding var text: String?
    var onEnter: () -> Void
    @State var frontReturnKeyType = OmenTextField.ReturnKeyType.next
    @State var isFocused: Focus?
    @State var tempText = ""
    
    enum Focus {
        case focused, notFocused
    }

    var body: some View {

            ScrollView(.vertical) {
                VStack {
                    OmenTextField(
                        "Type your message here",
                        text: $text.unwrapped(or: ""),
                        isFocused: $isFocused.equalTo(.focused),
                        returnKeyType: frontReturnKeyType,
                        onCommit: {
                            onEnter()
                        }
                    )
                    

                }
                .padding(8)
                .onAppear {
                    // update text if the $text is not empty
//                    print(">>>")
//                    print($text)
                    tempText = text ?? ""
                    text = ""

                    DispatchQueue.main.async {
                        text = tempText
                    }
                    isFocused = .focused
                    
                }
                
            }
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused == .focused ? Color.blue : Color.gray.opacity(0.5), lineWidth: isFocused == .focused ? 4 : 2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            )
            .onTapGesture {
                isFocused = .focused
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
            } else if wrappedValue == value {
                wrappedValue = nil
            }
        }
    }
}

extension Binding where Value == String? {
    func unwrapped(or defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

struct MessageInputView_Previews: PreviewProvider {
    static var previews: some View {
        MessageInputView(text: .constant("Some input message"), onEnter: {})
    }
}

