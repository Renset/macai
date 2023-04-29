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
    @Environment(\.colorScheme) var colorScheme
    
    func parseMessageFromString(input: String) -> [MessageElements] {
        let lines = input.split(separator: "\n").map { String($0) }
        var elements: [MessageElements] = []
        var currentHeader: [String] = []
        var currentTableData: [[String]] = []
        var delimiterFound = false
        var possibleTableNameFound = false
        var possibleTableName = ""
        var firstDataRow = true
        var tableName = ""
        var textLines: [String] = []
        var previousRowData: [String] = [""]
        var codeLines: [String] = []
        var isCodeBlockOpened = false
        var codeBlockLanguage = ""
        let highlightr = Highlightr()

        highlightr?.setTheme(to: colorScheme == .dark ? "monokai-sublime" : "color-brewer")

        for line in lines {
            if line.hasPrefix("```") {
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                toggleCodeBlock(line: line)
            } else if isCodeBlockOpened {
                codeLines.append(line)
            } else if isTableTitle(line: line) {
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                checkForTableName(line: line)
            } else if line.first == "|" {
                handleTableLine(line: line)
            } else {
                resetTableParameters()
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
            } else {
                codeBlockLanguage = line.replacingOccurrences(of: "```", with: "")
                isCodeBlockOpened = true
            }
        }
        
        func isTableTitle(line: String) -> Bool {
            return line.hasPrefix("**Table") || line.hasPrefix("**Таблица") ||
                   line.hasPrefix("Table") || line.hasPrefix("Таблица")
        }

        func checkForTableName(line: String) {
            if line.hasPrefix("**") {
                setTableName(name: line)
            } else {
                // We still can't be sure that the string with "Table" prefix is the real table header
                possibleTableNameFound = true
                possibleTableName = line
            }
        }
        
        func setTableName(name: String) {
            tableName = name.replacingOccurrences(of: "**", with: "")
        }

        func handleTableLine(line: String) {
            if possibleTableNameFound {
                setTableName(name: possibleTableName)
                resetPossibleTableName()
            }

            combineTextLinesIfNeeded()

            let rowData = parseRowData(line: line)

            if !delimiterFound {
                handleFirstRowData(rowData: rowData)
            } else {
                handleSubsequentRowData(rowData: rowData)
            }
            previousRowData = rowData
        }

        func parseRowData(line: String) -> [String] {
            return line.split(separator: "|")
                       .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                       .filter { !$0.isEmpty }
        }

        func handleFirstRowData(rowData: [String]) {
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
        }

        func handleSubsequentRowData(rowData: [String]) {
            if rowData.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) {
                appendTable()
                resetTableParameters()
                currentHeader = previousRowData
            } else {
                currentTableData.append(rowData)
            }
        }

        func resetTableParameters() {
            delimiterFound = false
        }

        func resetPossibleTableName() {
            possibleTableNameFound = false
            possibleTableName = ""
        }

        func combineTextLinesIfNeeded() {
            if !textLines.isEmpty {
                let combinedText = textLines.joined(separator: "\n")
                elements.append(.text(combinedText))
                textLines = []
            }
        }

        func appendTableIfNeeded() {
            if delimiterFound || !currentTableData.isEmpty {
                appendTable()
                firstDataRow = true
            }
        }
        
        func appendTable() {
            elements.append(.table(header: currentHeader, data: currentTableData, name: tableName))
            currentHeader = []
            currentTableData = []
            resetTableParameters()
            resetPossibleTableName()
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

                elements.append(.code(code: highlightedCode, lang: codeBlockLanguage))
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



