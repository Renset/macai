//
//  ThemeMode.swift
//  macai
//
//  Created by Renat on 08.02.2025.
//

import SwiftUI

enum ThemeMode {
    case system
    case light
    case dark
}

struct ThemeButton: View {
    let title: String
    let isSelected: Bool
    let mode: ThemeMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    if mode == .system {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 35)
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 35)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(backgroundColor)
                    }

                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray.opacity(0.5), lineWidth: 0.5)
                        .frame(width: 70, height: 50)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(Color.red.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(Color.yellow.opacity(0.8))
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(Color.green.opacity(0.8))
                                .frame(width: 6, height: 6)
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: 70, alignment: .leading)
                        .padding(.leading, 4)

                        Group {
                            switch mode {
                            case .system:
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        Text("  Lorem")
                                            .foregroundColor(.black)
                                            .frame(width: 35)
                                        Text("ipsum  ")
                                            .foregroundColor(.white)
                                            .frame(width: 35)
                                    }
                                    HStack(spacing: 0) {
                                        Capsule()
                                            .fill(Color.yellow.opacity(0.6))
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                                            )
                                            .shadow(
                                                color: Color.yellow.opacity(0.7),
                                                radius: 4
                                            )
                                            .frame(width: 24, height: 8)
                                            .frame(width: 35)
                                    }
                                    .padding(.top, 6)
                                }
                            case .light:
                                VStack(spacing: 0) {
                                    Text("Lorem ipsum")
                                        .foregroundColor(.black)
                                        .frame(width: 70)

                                    Capsule()
                                        .fill(Color.yellow.opacity(0.6))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                                        )
                                        .shadow(
                                            color: Color.yellow.opacity(0.7),
                                            radius: 4
                                        )
                                        .frame(width: 24, height: 8)
                                        .padding(.top, 6)
                                }
                            case .dark:
                                VStack(spacing: 0) {
                                    Text("Lorem ipsum")
                                        .foregroundColor(.white)
                                        .frame(width: 70)

                                    Capsule()
                                        .fill(Color.yellow.opacity(0.6))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                                        )
                                        .shadow(
                                            color: Color.yellow.opacity(0.7),
                                            radius: 4
                                        )
                                        .frame(width: 24, height: 8)
                                        .padding(.top, 6)
                                }
                            }
                        }
                        .font(.system(size: 8))

                        Spacer()
                    }
                    .frame(width: 70)
                }
                .frame(width: 70, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch mode {
        case .system:
            return Color.clear
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }
}
