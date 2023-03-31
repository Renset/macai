//
//  ChatBubbleView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import Foundation
import SwiftUI
import Highlightr
import AttributedText

enum TableElement {
    case text(String)
    case table(header: [String], data: [[String]], name: String)
    case code(code: NSAttributedString?, lang: String)
}

struct ChatBubbleView: View {
    var message: String = ""
    @State var index: Int
    @State var own: Bool
    @State var waitingForResponse: Bool?
    @State var error = false
    @State var initialMessage = false
    @State private var isPencilIconVisible = false
    @State private var wobbleAmount = 0.0
    @Environment(\.colorScheme) var colorScheme
    
    @State private var messageAttributeString: NSAttributedString?
    @State private var attributedStrings: [Int: NSAttributedString] = [:]
    @State private var codeHighlighted: Bool = false
    
#if os(macOS)
    var outgoingBubbleColor = NSColor.systemBlue
    var incomingBubbleColor = NSColor.windowBackgroundColor
    var incomingLabelColor = NSColor.labelColor
#else
    var outgoingBubbleColor = UIColor.systemBlue
    var incomingBubbleColor = UIColor.secondarySystemBackground
    var incomingLabelColor = UIColor.label
#endif
    
    
    
    var body: some View {
        HStack {
            if own {
                Spacer()
            }
            
                VStack(alignment: .leading) {
                    if (self.waitingForResponse ?? false) {
                        
                        HStack() {
                            //self.isPencilIconVisible = true
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .offset(x: wobbleAmount, y: 0)
                                //.rotationEffect(.degrees(-wobbleAmount * 0.1))
                                .animation(
                                    .easeIn(duration: 0.5).repeatForever(autoreverses: true), value: wobbleAmount
                                )
                                .onAppear {
                                    wobbleAmount = 20
                                }
                            Spacer()

                        }
                        // set width
                        .frame(width: 30)
                    } else if (self.error) {
                        VStack {
                            HStack() {
                                //self.isPencilIconVisible = true
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundColor(.white)
                                Text("Error getting message from server. Try again?")
                            }
                        }
                    } else {

                        let elements = parseTableFromString(input: message)

                        // Display the elements
                        ForEach(0..<elements.count, id: \.self) { index in
                            switch elements[index] {
                            case .text(let text):

                                Text(text)
                                    .textSelection(.enabled)
                            case .table(let header, let data, let name):
                                TableView(header: header, tableData: data, tableName: name)
                                    .padding()
                            
                            case .code(let code, let lang):
                                VStack {
                                    if (lang != "") {
                                        HStack {
                                            
                                            Text(lang)
                                                .fontWeight(.bold)
                                            
                                            Spacer()
                                        }
                                        .padding(.bottom, 2)
                                    }
                                    VStack {
                                        
                                        
                                        AttributedText(code ?? NSAttributedString(string: ""))
                                            .textSelection(.enabled)
                                            .padding(12)
                                        
                                        }
                                    
                                    
                                    
                                    .background(colorScheme == .dark ? Color(NSColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1)) : .white)
               
                                    
                                    .cornerRadius(8)
                                    
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                                
                                
                            }
                        }
                    }
                    
                }
                .foregroundColor(error ? Color(.white) : Color(own ? .white : incomingLabelColor))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(error ? Color(.red) : initialMessage ? Color(.systemPurple) : Color(own ? outgoingBubbleColor : incomingBubbleColor))
                .cornerRadius(16)
                

            
            if !own {
                Spacer()
            }
        }
        
        
    }
    
    func parseTableFromString(input: String) -> [TableElement] {
        let lines = input.split(separator: "\n").map { String($0) }
        var elements: [TableElement] = []
        var currentHeader: [String] = []
        var currentTableData: [[String]] = []
        var delimiterFound = false
        var tableNameFound = false
        var possibleTableNameFound = false
        var possibleTableName = ""
        var firstDataRow = true // assume first line as header if no delimiter is found in response
        var tableName = ""
        var textLines: [String] = []
        var previousRowData: [String] = [""]
        var codeLines: [String] = []
        var codeBlockFound = false
        var codeBlockLanguage = ""
        let highlightr = Highlightr()
    
        highlightr?.setTheme(to: colorScheme == .dark ? "monokai-sublime" : "color-brewer")
        
        //let _ = print(input)

        for line in lines {
            if line.hasPrefix("```") {
                if codeBlockFound {
                    
                    if !codeLines.isEmpty {
                        let combinedCode = codeLines.joined(separator: "\n")
                        let highlightedCode: NSAttributedString?
                        
                        if (codeBlockLanguage != "") {
                            highlightedCode = highlightr?.highlight(combinedCode, as: codeBlockLanguage)
                        } else {
                            highlightedCode = highlightr?.highlight(combinedCode)
                        }
                        
                        elements.append(.code(code: highlightedCode, lang: codeBlockLanguage))
                    }
                    codeBlockFound = false
                    codeBlockLanguage = ""
                } else {
                    codeBlockLanguage = line.replacingOccurrences(of: "```", with: "")
                    codeBlockFound = true
                }
            } else if codeBlockFound {
                codeLines.append(line)
            } else if line.hasPrefix("**Table") || line.hasPrefix("**Таблица") {
                if delimiterFound || !currentTableData.isEmpty {
                    elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
                    currentHeader = []
                    currentTableData = []
                    delimiterFound = false
                    firstDataRow = true
                }
                
                tableNameFound = true
                tableName = line.replacingOccurrences(of: "**", with: "")

            } else if line.hasPrefix("Table") || line.hasPrefix("Таблица") {
                if delimiterFound || !currentTableData.isEmpty {
                    elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
                    currentHeader = []
                    currentTableData = []
                    delimiterFound = false
                    firstDataRow = true
                }
                
                possibleTableNameFound = true
                possibleTableName = line
            } else if line.first == "|" {
                if possibleTableNameFound {
                    tableNameFound = true
                    tableName = possibleTableName
                    possibleTableNameFound = false
                    possibleTableName = ""
                }
                if !textLines.isEmpty {
                    let combinedText = textLines.joined(separator: "\n")
                    elements.append(.text(combinedText))
                    textLines = []
                }

                let rowData = line.split(separator: "|")
                                 .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                                 .filter { !$0.isEmpty }
                
                
                
                if !delimiterFound {
                    print(rowData)
                    if rowData.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) {
                        delimiterFound = true
                    } else {
                        if firstDataRow {
                            currentHeader = rowData
                            firstDataRow = false
                        } else {
                            currentTableData.append(rowData)
                        }
                    }
                } else {
                    let _ = print("second table found")
                    if rowData.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) {
                        elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
                        currentHeader = []
                        currentTableData = []
                        delimiterFound = true
                        firstDataRow = true
                        
                        currentHeader = previousRowData
                    } else {
                        currentTableData.append(rowData)
                    }
                }
                
                previousRowData = rowData
            } else {
                delimiterFound = false
                tableNameFound = false
                if (!currentTableData.isEmpty) {
                    elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
                }
                
                currentHeader = []
                currentTableData = []
                firstDataRow = true
                
                if (possibleTableNameFound) {
                    textLines.append(possibleTableName)
                    possibleTableNameFound = false
                    possibleTableName = ""
                }
                
                
                elements.append(.text(line))
                
            }
        
        }

        if !currentHeader.isEmpty && !currentTableData.isEmpty {
            elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
        }

        if !textLines.isEmpty {
            let combinedText = textLines.joined(separator: "\n")
            elements.append(.text(combinedText))
        }

        return elements
    }
}
