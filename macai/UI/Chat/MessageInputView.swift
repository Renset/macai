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
    @State var dynamicHeight: CGFloat = 16
    private let maxInputHeight = 160.0
    private let initialInputSize = 16.0
    private let inputPadding = 8.0
    private let lineWidthOnBlur = 2.0
    private let lineWidthOnFocus = 3.0
    private let lineColorOnBlur = Color.gray.opacity(0.5)
    private let lineColorOnFocus = Color.blue.opacity(0.8)
    private let cornerRadius = 8.0
    private let inputPlaceholderText = "Type your prompt here"

    enum Focus {
        case focused, notFocused
    }

    var body: some View {
        ZStack {
            // Hidden text view for dynamic height calculation
            Text(text)
                .font(.body)
                .lineLimit(10)
                .background(GeometryReader { geometryText in
                    Color.clear
                        .onAppear {
                            dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                        }
                        .onChange(of: geometryText.size) { _ in
                            dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                        }
                })
                .padding(inputPadding)
                .hidden()
            
            ScrollView {
                VStack {
                    OmenTextField(
                        inputPlaceholderText,
                        text: $text,
                        isFocused: $isFocused.equalTo(.focused),
                        returnKeyType: frontReturnKeyType,
                        onCommit: {
                            onEnter()
                        }
                    )
                    
                }
                .padding(inputPadding/2)
            }
            .padding(inputPadding/2)
            .frame(height: dynamicHeight)
            .background(Color.clear)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isFocused == .focused ? lineColorOnFocus : lineColorOnBlur,
                        lineWidth: isFocused == .focused ? lineWidthOnFocus : lineWidthOnBlur
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .onTapGesture {
                isFocused = .focused
            }
        }
    }
    
    private func calculateDynamicHeight(using height: CGFloat? = nil) -> CGFloat {
        let newHeight = height ?? dynamicHeight
        return min(max(newHeight, initialInputSize), maxInputHeight) + inputPadding*2
    }
}

struct MessageInputView_Previews: PreviewProvider {
    static var previews: some View {
        MessageInputView(text: .constant("Some input message"), onEnter: {})
    }
}
