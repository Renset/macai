//
//  MessageParser.swift
//  macai
//
//  Created by Renat Notfullin on 25.04.2023.
//

import Foundation
import Highlightr
import SwiftUI

struct MessageParser {
    @State var colorScheme: ColorScheme
    
    func parseMessageFromString(input: String) -> [MessageElements] {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var elements: [MessageElements] = []
        var currentHeader: [String] = []
        var currentTableData: [[String]] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var firstTableRowProcessed = false
        var isCodeBlockOpened = false
        var codeBlockLanguage = ""
        let highlightr = Highlightr()
        var leadingSpaces = 0

        highlightr?.setTheme(to: colorScheme == .dark ? "monokai-sublime" : "color-brewer")

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                // memorize how many leading spaces the line has
                leadingSpaces = line.count - line.trimmingCharacters(in: .whitespaces).count
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                toggleCodeBlock(line: line)
            } else if isCodeBlockOpened {
                if (leadingSpaces > 0) {
                    codeLines.append(String(line.dropFirst(leadingSpaces)))
                } else {
                    codeLines.append(line)
                }
            }  else if line.trimmingCharacters(in: .whitespaces).first == "|" {
                handleTableLine(line: line)
            } else {
                if !currentTableData.isEmpty {
                    appendTable()
                }
                textLines.append(line)
            }
        }

        finalizeParsing()
        
        func toggleCodeBlock(line: String) {
            if isCodeBlockOpened {
                appendCodeBlockIfNeeded()
                isCodeBlockOpened = false
                codeBlockLanguage = ""
                leadingSpaces = 0
            } else {
                // extract codeBlockLanguage and remove leading spaces
                codeBlockLanguage = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "```", with: "")
                isCodeBlockOpened = true
            }
        }

        func handleTableLine(line: String) {

            combineTextLinesIfNeeded()

            let rowData = parseRowData(line: line)
            
            if (rowDataIsTableDelimiter(rowData: rowData)) {
                return
            }

            if !firstTableRowProcessed {
                handleFirstRowData(rowData: rowData)
            } else {
                handleSubsequentRowData(rowData: rowData)
            }
        }
        
        func rowDataIsTableDelimiter(rowData: [String]) -> Bool {
            return rowData.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) })
        }
    

        func parseRowData(line: String) -> [String] {
            return line.split(separator: "|")
                       .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                       .filter { !$0.isEmpty }
        }

        func handleFirstRowData(rowData: [String]) {
            currentHeader = rowData
            firstTableRowProcessed = true
        }

        func handleSubsequentRowData(rowData: [String]) {
            currentTableData.append(rowData)
        }

        func combineTextLinesIfNeeded() {
            if !textLines.isEmpty {
                let combinedText = textLines.reduce("") { (result, line) -> String in
                    if result.isEmpty {
                        return line
                    } else {
                        return result + "\n" + line
                    }
                }
                elements.append(.text(combinedText))
                textLines = []
            }
        }

        func appendTableIfNeeded() {
            if !currentTableData.isEmpty {
                appendTable()
            }
        }
        
        func appendTable() {
            elements.append(.table(header: currentHeader, data: currentTableData))
            currentHeader = []
            currentTableData = []
            firstTableRowProcessed = false
        }

        func appendCodeBlockIfNeeded() {
            if !codeLines.isEmpty {
                let combinedCode = codeLines.joined(separator: "\n")
                let highlightedCode: NSAttributedString?

                if !codeBlockLanguage.isEmpty {
                    highlightedCode = highlightr?.highlight(combinedCode, as: codeBlockLanguage)
                } else {
                    highlightedCode = highlightr?.highlight(combinedCode)
                }

                elements.append(.code(code: highlightedCode, lang: codeBlockLanguage, indent: leadingSpaces))
                codeLines = []
            }
        }

        func finalizeParsing() {
            combineTextLinesIfNeeded()
            appendCodeBlockIfNeeded()
            appendTableIfNeeded()
        }

        return elements
    }
}



