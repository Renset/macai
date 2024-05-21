//
//  Accordion.swift
//  macai
//
//  Created by Renat on 22.05.2024.
//

import SwiftUI

struct Accordion<Content: View>: View {
    @State private var isExpanded: Bool
    let content: Content
    let title: String

    init(title: String, isExpanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content()
    }
    
    var body: some View {
        VStack() {
            Button(action: {
                withAnimation {
                    self.isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .frame(alignment:.leading)
                    Image(systemName: isExpanded ? "arrow.down.circle" : "arrow.up.circle")
                }
            }
            if isExpanded {
                content
                    .padding()
            }
        }
    }
}

#Preview {
    Accordion(title: "Accordion", isExpanded: true) {
        Text("This is the content of Accordion")
    }
}
