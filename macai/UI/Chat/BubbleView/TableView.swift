//
//  TableView.swift
//  macai
//
//  Created by Renat Notfullin on 15.03.2023.
//

import Foundation
import SwiftUI
import AppKit


struct TableHeaderView: View {
    let header: [String]
    @Binding var searchText: String
    var message: MessageEntity?
    var currentSearchOccurrence: SearchOccurrence?
    var originalContent: String
    let elementIndex: Int

    var body: some View {
        HStack {
            ForEach(header.indices, id: \.self) { index in
                HighlightedText(
                    header[index],
                    highlight: searchText,
                    message: message,
                    currentSearchOccurrence: currentSearchOccurrence,
                    originalContent: originalContent,
                    elementIndex: elementIndex
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                if index < header.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color.gray.opacity(0.15))
    }
}

struct TableRowView: View {
    let rowData: [String]
    let rowIndex: Int
    @Binding var searchText: String
    var message: MessageEntity?
    var currentSearchOccurrence: SearchOccurrence?
    var originalContent: String
    let elementIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<rowData.count, id: \.self) { columnIndex in
                HighlightedText(
                    rowData[columnIndex],
                    highlight: searchText,
                    message: message,
                    currentSearchOccurrence: currentSearchOccurrence,
                    originalContent: originalContent,
                    elementIndex: elementIndex
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                
                if columnIndex < rowData.count - 1 {
                    Divider()
                }
            }
        }
        .background(rowIndex % 2 == 0 ? Color.gray.opacity(0.1) : Color.clear)
    }
}

struct TableView: View {
    let header: [String]
    let tableData: [[String]]
    @Binding var searchText: String
    var message: MessageEntity?
    var currentSearchOccurrence: SearchOccurrence?
    let elementIndex: Int
    @State private var isCopied = false
    @State private var isCopiedJSON = false
    
    private func copyTableToClipboard() {
        let headerString = header.joined(separator: "\t")
        let tableDataString = tableData.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        let tableString = "\(headerString)\n\(tableDataString)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tableString, forType: .string)
    }
    
    private func copyTableAsJSONToClipboard() {
        let tableDictArray = tableData.map { rowData -> [String: String] in
            var rowDict: [String: String] = [:]
            for (index, value) in rowData.enumerated() {
                rowDict[header[index]] = value
            }
            return rowDict
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: tableDictArray, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(jsonString, forType: .string)
                #elseif os(iOS)
                UIPasteboard.general.string = jsonString
                #endif
            }
        } catch {
            print("Failed to convert table data to JSON string: \(error)")
        }
    }
    

    var body: some View {
        let originalContent = message?.body ?? ""
        
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    copyTableAsJSONToClipboard()
                    withAnimation{
                        isCopiedJSON = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            isCopiedJSON = false
                        }
                    }
                }) {
                    Image(systemName: isCopiedJSON ? "checkmark" : "doc.on.doc")
                    Text("JSON")
                }
                .padding(0)
                .padding(.trailing, 16)
                .buttonStyle(PlainButtonStyle())

                
                Button(action: {
                    copyTableToClipboard()
                    withAnimation{
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                }
                .padding(0)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 2)
            VStack(spacing: 0) {
                
                // Display the table header
                TableHeaderView(
                    header: header,
                    searchText: $searchText,
                    message: message,
                    currentSearchOccurrence: currentSearchOccurrence,
                    originalContent: originalContent,
                    elementIndex: elementIndex
                )
                
                // Add a horizontal line under the table header
                Divider()
                
                // Display the table body
                ForEach(0..<tableData.count, id: \.self) { rowIndex in
                    TableRowView(
                         rowData: tableData[rowIndex],
                         rowIndex: rowIndex,
                         searchText: $searchText,
                         message: message,
                         currentSearchOccurrence: currentSearchOccurrence,
                         originalContent: originalContent,
                         elementIndex: elementIndex
                     )
                    
                    // Add a horizontal line between rows
                    if rowIndex < tableData.count - 1 {
                        Divider()
                    }
                }
            }
            .cornerRadius(8)
            .padding(.top, 0)
        }
        
        

    }
}
