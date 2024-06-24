//
//  MathView.swift
//  macai
//
//  Created by Renat on 24.06.2024.
//

import SwiftUI
import SwiftMath

struct MathViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MathView: NSViewRepresentable {
    var equation: String
    var fontSize: CGFloat
    
    func makeNSView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.font = MTFontManager().termesFont(withSize: fontSize)
        view.textColor = .textColor
        view.textAlignment = .left
        view.labelMode = .text
        return view
    }
    
    func updateNSView(_ view: MTMathUILabel, context: Context) {
        view.latex = equation
        view.fontSize = fontSize
        view.setNeedsDisplay(view.bounds)
    }
}

struct AdaptiveMathView: View {
    let equation: String
    let fontSize: CGFloat
    @State private var size: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            MathView(equation: equation, fontSize: fontSize)
                .background(GeometryReader { innerGeometry in
                    Color.clear.preference(key: MathViewSizePreferenceKey.self, value: innerGeometry.size)
                })
                .onPreferenceChange(MathViewSizePreferenceKey.self) { newSize in
                    DispatchQueue.main.async {
                        self.size = newSize
                    }
                }
        }
        .frame(width: size.width, height: size.height)
    }
}

