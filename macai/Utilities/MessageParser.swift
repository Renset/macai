//
//  MessageParser.swift
//  macai
//
//  Created by Renat Notfullin on 25.04.2023.
//

import Foundation
import Highlightr
import SwiftUI
import CoreData
import CommonCrypto

struct MessageParser {
    @State var colorScheme: ColorScheme
    
    enum BlockType {
        case text
        case table
        case codeBlock
        case formulaBlock
        case formulaLine
    }
    
    func detectBlockType(line: String) -> BlockType {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        if trimmedLine.hasPrefix("```") {
            return .codeBlock
        } else if trimmedLine.first == "|" {
            return .table
        } else if trimmedLine.hasPrefix("\\[") {
            return trimmedLine.replacingOccurrences(of: " ", with: "") == "\\[" ? .formulaBlock : .formulaLine
        } else if trimmedLine.hasPrefix("\\]") {
            return .formulaLine
        } else {
            return .text
        }
    }
    
    func parseMessageFromString(input: String, shouldSkipCodeHighlighting: Bool) -> [MessageElements] {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var elements: [MessageElements] = []
        var currentHeader: [String] = []
        var currentTableData: [[String]] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var formulaLines: [String] = []
        var firstTableRowProcessed = false
        var isCodeBlockOpened = false
        var isFormulaBlockOpened = false
        var codeBlockLanguage = ""
        let highlightr = Highlightr()
        var leadingSpaces = 0

        highlightr?.setTheme(to: colorScheme == .dark ? "monokai-sublime" : "color-brewer")
        
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
        
        func openFormulaBlock() {
            isFormulaBlockOpened = true
        }
        
        func closeFormulaBlock() {
            isFormulaBlockOpened = false
        }
        
        func handleFormulaLine(line: String) {
            let formulaString = line.replacingOccurrences(of: "\\[", with: "").replacingOccurrences(of: "\\]", with: "")
            formulaLines.append(formulaString)
        }
        
        func appendFormulaLines() {
            let combinedLines = formulaLines.joined(separator: "\n")
            elements.append(.formula(combinedLines))
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

                if shouldSkipCodeHighlighting == true {
                    let systemSize = NSFont.systemFontSize
                    let font = NSFont.monospacedSystemFont(ofSize: systemSize, weight: .regular)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font
                    ]
                    
                    highlightedCode = NSAttributedString(string: combinedCode, attributes: attributes)
                } else {
                    highlightedCode = highlightr?.highlight(combinedCode, as: codeBlockLanguage.isEmpty ? nil : codeBlockLanguage)
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
        
        for line in lines {
            let blockType = detectBlockType(line: line)
            
            switch blockType {
            case .codeBlock:
                leadingSpaces = line.count - line.trimmingCharacters(in: .whitespaces).count
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                toggleCodeBlock(line: line)
                
            case .table:
                handleTableLine(line: line)
                
            case .formulaBlock:
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                openFormulaBlock()
                
            case .formulaLine:
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("\\]") {
                    closeFormulaBlock()
                    appendFormulaLines()
                } else {
                    handleFormulaLine(line: line)
                    if !isFormulaBlockOpened {
                        appendFormulaLines()
                    }
                }
                
            case .text:
                if isCodeBlockOpened {
                    if leadingSpaces > 0 {
                        codeLines.append(String(line.dropFirst(leadingSpaces)))
                    } else {
                        codeLines.append(line)
                    }
                } else if isFormulaBlockOpened {
                    handleFormulaLine(line: line)
                } else {
                    if !currentTableData.isEmpty {
                        appendTable()
                    }
                    textLines.append(line)
                }
            }
        }

        finalizeParsing()

        return elements
    }
}
