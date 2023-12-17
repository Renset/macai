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
    @State var tempText = ""

    enum Focus {
        case focused, notFocused
    }

    var body: some View {

        ScrollView(.vertical) {
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
        .frame(height: getFrameHeight(inputText: text))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused == .focused ? Color.blue : Color.gray.opacity(0.5),
                    lineWidth: isFocused == .focused ? 4 : 2
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        .onTapGesture {
            isFocused = .focused
        }
    }
}

private func getFrameHeight(inputText: String) -> CGFloat? {
    if inputText.count > 250 {
        return 96
    }
    
    if inputText.count > 120 {
        return 64
    }
    
    if inputText.count > 80 {
        return 48
    }
    
    let lineBreakCount = inputText.split(separator: "\n", maxSplits: 6, omittingEmptySubsequences: false).count - 1
    
    if lineBreakCount > 0 {
        return 32 + CGFloat(lineBreakCount * 16)
    }
    
    return 32
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
