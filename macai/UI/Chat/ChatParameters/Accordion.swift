//
//  Accordion.swift
//  macai
//
//  Created by Renat on 22.05.2024.
//

import SwiftUI

struct Accordion<Content: View>: View {
    var icon: String? = nil
    let title: String
    @State private var isExpanded: Bool
    let content: Content
    var isButtonHidden: Bool = false

    init(
        icon: String?,
        title: String,
        isExpanded: Bool = false,
        isButtonHidden: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self._isExpanded = State(initialValue: isExpanded)
        self.isButtonHidden = isButtonHidden
        self.content = content()
    }

    var body: some View {
        VStack {
            if !isButtonHidden {
                HStack {
                    Button(action: {
                        withAnimation {
                            self.isExpanded.toggle()
                        }
                    }) {
                        HStack {
                            if !isExpanded {
                                if let icon = icon {
                                    Image(icon)
                                        .resizable()
                                        .renderingMode(.template)
                                        .interpolation(.high)
                                        .antialiased(true)
                                        .frame(width: 12, height: 12)
                                }
                            }

                            Text(title)
                                .frame(alignment: .leading)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        }
                    }
                }
                .padding(.horizontal, 32)

            }
            if isExpanded {
                content
                    .padding()
            }
        }
    }
}

#Preview {
    Accordion(icon: "logo_ollama", title: "Accordion", isExpanded: true) {
        Text("This is the content of Accordion")
    }
}
