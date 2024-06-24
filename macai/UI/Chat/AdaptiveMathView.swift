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
        view.labelMode = .display
        return view
    }
    
    func updateNSView(_ view: MTMathUILabel, context: Context) {
        view.latex = equation
        view.fontSize = fontSize
        DispatchQueue.main.async {
            context.coordinator.updateSize(for: view)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MathView
        
        init(_ parent: MathView) {
            self.parent = parent
            super.init()
        }
        
        func updateSize(for view: MTMathUILabel) {
            let size = view.intrinsicContentSize
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("MathViewSizeChanged"), object: size)
            }
        }
    }
}

struct AdaptiveMathView: View {
    let equation: String
    let fontSize: CGFloat
    @State private var size: CGSize = .zero
    
    var body: some View {
        MathView(equation: equation, fontSize: fontSize)
            .frame(width: size.width, height: size.height)
            .onReceive(NotificationCenter.default.publisher(for: .init("MathViewSizeChanged"))) { notification in
                if let newSize = notification.object as? CGSize {
                    self.size = newSize
                }
            }
    }
}
