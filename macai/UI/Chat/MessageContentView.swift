//
//  MessageContentView.swift
//  macai
//
//  Created by Renat on 23.06.2024.
//

import SwiftUI

struct MessageContentView: View {
    @State private var parsedElements: [MessageElements] = []
    @Binding var isStreaming: Bool
    var message: String
    let colorScheme: ColorScheme
    var viewContext: NSManagedObjectContext
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(0..<parsedElements.count, id: \.self) { index in
                switch parsedElements[index] {
                case .text(let text):
                    Text(.init(text))
                        .textSelection(.enabled)
                case .table(let header, let data):
                    TableView(header: header, tableData: data)
                        .padding()
                case .code(let code, let lang, let indent):
                    CodeView(code: code, lang: lang)
                        .padding(.bottom, 8)
                        .padding(.leading, CGFloat(indent)*4)
                }
            }
        }
        .onChange(of: message) { _ in
            parseMessage()
        }
        .onChange(of: isStreaming) { _ in
            parseMessage()
        }
        .onAppear {
            parseMessage()
        }

    }
    
    private func parseMessage() {
        let parser = MessageParser(colorScheme: colorScheme, viewContext: viewContext)
        parsedElements = parser.parseMessageFromString(input: message, shouldSkipCodeHighlighting: isStreaming)
    }
}

//#Preview {
//    //MessageContentView()
//}
