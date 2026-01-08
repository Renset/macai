import CoreData
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

    enum BlockType {
        case text
        case table
        case codeBlock
        case formulaBlock
        case formulaLine
        case thinking
        case imageUUID
    }

    func detectBlockType(line: String) -> BlockType {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.hasPrefix("<think>") {
            return .thinking
        }
        else if trimmedLine.hasPrefix("```") {
            return .codeBlock
        }
        else if trimmedLine.first == "|" {
            return .table
        }
        else if trimmedLine.hasPrefix("\\[") {
            return trimmedLine.replacingOccurrences(of: " ", with: "") == "\\[" ? .formulaBlock : .formulaLine
        }
        else if trimmedLine.hasPrefix("\\]") {
            return .formulaLine
        }
        else if trimmedLine.hasPrefix("<image-uuid>") {
            return .imageUUID
        }
        else {
            return .text
        }
    }

    func parseMessageFromString(input: String) -> [MessageElements] {

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
        var leadingSpaces = 0

        func toggleCodeBlock(line: String) {
            if isCodeBlockOpened {
                appendCodeBlockIfNeeded()
                isCodeBlockOpened = false
                codeBlockLanguage = ""
                leadingSpaces = 0
            }
            else {
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

            if rowDataIsTableDelimiter(rowData: rowData) {
                return
            }

            if !firstTableRowProcessed {
                handleFirstRowData(rowData: rowData)
            }
            else {
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
                    }
                    else {
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
                elements.append(.code(code: combinedCode, lang: codeBlockLanguage, indent: leadingSpaces))
                codeLines = []
            }
        }

        func handleLineWithInlineImages(_ line: String, isLastLine: Bool) {
            let pattern = "<image-uuid>(.*?)</image-uuid>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                textLines.append(line)
                return
            }

            let nsString = line as NSString
            let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsString.length))

            guard !matches.isEmpty else {
                textLines.append(line)
                return
            }

            var currentLocation = 0
            var pendingText = ""

            func flushPendingText(allowEmptyNewline: Bool = false) {
                guard !pendingText.isEmpty || allowEmptyNewline else { return }
                elements.append(.text(pendingText))
                pendingText = ""
            }

            for match in matches {
                let matchRange = match.range
                let textLength = matchRange.location - currentLocation
                if textLength > 0 {
                    let segment = nsString.substring(with: NSRange(location: currentLocation, length: textLength))
                    pendingText += segment
                }

                if !pendingText.isEmpty {
                    flushPendingText()
                }

                var appendedImage = false
                if match.numberOfRanges > 1 {
                    let uuidRange = match.range(at: 1)
                    let uuidString = nsString.substring(with: uuidRange)
                    if let uuid = UUID(uuidString: uuidString), let image = loadImageFromCoreData(uuid: uuid) {
                        elements.append(.image(image))
                        appendedImage = true
                    }
                }

                if !appendedImage {
                    let placeholder = nsString.substring(with: matchRange)
                    pendingText += placeholder
                }

                currentLocation = matchRange.location + matchRange.length

                if !pendingText.isEmpty {
                    flushPendingText()
                }
            }

            if currentLocation < nsString.length {
                let trailing = nsString.substring(from: currentLocation)
                pendingText += trailing
            }

            if !pendingText.isEmpty {
                if !isLastLine {
                    pendingText += "\n"
                }
                flushPendingText()
            }
            else if !isLastLine {
                pendingText = "\n"
                flushPendingText(allowEmptyNewline: true)
            }
        }

        func loadImageFromCoreData(uuid: UUID) -> NSImage? {
            let viewContext = PersistenceController.shared.container.viewContext

            let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1

            do {
                let results = try viewContext.fetch(fetchRequest)
                if let imageEntity = results.first, let imageData = imageEntity.image {
                    return NSImage(data: imageData)
                }
            }
            catch {
                print("Error fetching image from CoreData: \(error)")
            }

            return nil
        }

        var thinkingLines: [String] = []
        var isThinkingBlockOpened = false

        func appendThinkingBlockIfNeeded() {
            if !thinkingLines.isEmpty {
                let combinedThinking = thinkingLines.joined(separator: "\n")
                    .replacingOccurrences(of: "<think>", with: "")
                    .replacingOccurrences(of: "</think>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                elements.append(.thinking(combinedThinking, isExpanded: false))
                thinkingLines = []
            }
        }

        func finalizeParsing() {
            combineTextLinesIfNeeded()
            appendCodeBlockIfNeeded()
            appendTableIfNeeded()
            appendThinkingBlockIfNeeded()
        }

        for (index, line) in lines.enumerated() {
            let isLastLine = index == lines.count - 1
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
                }
                else {
                    handleFormulaLine(line: line)
                    if !isFormulaBlockOpened {
                        appendFormulaLines()
                    }
                }

            case .thinking:
                if line.contains("</think>") {
                    let thinking =
                        line
                        .replacingOccurrences(of: "<think>", with: "")
                        .replacingOccurrences(of: "</think>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    elements.append(.thinking(thinking, isExpanded: false))
                }
                else if line.contains("<think>") {
                    combineTextLinesIfNeeded()
                    appendTableIfNeeded()
                    isThinkingBlockOpened = true

                    let firstLine = line.replacingOccurrences(of: "<think>", with: "")
                    if !firstLine.isEmpty {
                        thinkingLines.append(firstLine)
                    }
                }

            case .imageUUID:
                // Handle inline image tags even when the line starts with <image-uuid>
                // to avoid dropping trailing text after the image tag.
                combineTextLinesIfNeeded()
                appendTableIfNeeded()
                handleLineWithInlineImages(line, isLastLine: isLastLine)

            case .text:
                if isThinkingBlockOpened {
                    if line.contains("</think>") {
                        let lastLine = line.replacingOccurrences(of: "</think>", with: "")
                        if !lastLine.isEmpty {
                            thinkingLines.append(lastLine)
                        }
                        isThinkingBlockOpened = false
                        appendThinkingBlockIfNeeded()
                    }
                    else {
                        thinkingLines.append(line)
                    }
                }
                else if isCodeBlockOpened {
                    if leadingSpaces > 0 {
                        codeLines.append(String(line.dropFirst(leadingSpaces)))
                    }
                    else {
                        codeLines.append(line)
                    }
                }
                else if isFormulaBlockOpened {
                    handleFormulaLine(line: line)
                }
                else {
                    if line.contains("<image-uuid>") {
                        combineTextLinesIfNeeded()
                        appendTableIfNeeded()
                        handleLineWithInlineImages(line, isLastLine: isLastLine)
                        continue
                    }
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
