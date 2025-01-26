//
//  ErrorMessage.swift
//  macai
//
//  Created by Renat Notfullin on 01.12.2024.
//

import SwiftUI

struct ErrorMessage {
    let type: APIError
    let timestamp: Date
    var retryCount: Int = 0

    var displayTitle: String {
        switch type {
        case .requestFailed(_):
            return "Connection Error"
        case .invalidResponse:
            return "Invalid Response"
        case .decodingFailed(_):
            return "Processing Error"
        case .unauthorized:
            return "Authentication Error"
        case .rateLimited:
            return "Rate Limited"
        case .serverError(_):
            return "Server Error"
        case .unknown(_):
            return "Unknown Error"
        case .noApiService(_):
            return "No API Service selected"
        }
    }

    var displayMessage: String {
        switch type {
        case .requestFailed(let error):
            return "Failed to connect: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from server"
        case .decodingFailed(let message):
            return "Failed to process response: \(message)"
        case .unauthorized:
            return "Invalid API key or unauthorized access"
        case .rateLimited:
            return "Too many requests. Please wait a moment"
        case .serverError(let message):
            return message
        case .unknown(let message):
            return message
        case .noApiService(let message):
            return message
        }
    }

    var canRetry: Bool {
        switch type {
        case .unauthorized: return false
        default: return retryCount < 3
        }
    }
}

struct ErrorBubbleView: View {
    let error: ErrorMessage
    let onRetry: () -> Void
    let onIgnore: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .padding(.top, 1)

                VStack(alignment: .leading) {
                    HStack {
                        Text(error.displayTitle)
                            .font(.headline)
                            .foregroundColor(.white)

                        if error.canRetry {
                            Button(action: onRetry) {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .clipShape(Capsule())
                            .frame(height: 12)
                        }
                    }

                    if isExpanded {
                        Text(error.displayMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 4)
                            .textSelection(.enabled)
                    }
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.orange.opacity(0.8))
        .cornerRadius(16)
    }
}

#Preview {
    VStack(spacing: 20) {
        ErrorBubbleView(
            error: ErrorMessage(
                type: .requestFailed(NSError(domain: "network", code: -1009)),
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {}
        )

        ErrorBubbleView(
            error: ErrorMessage(
                type: .unauthorized,
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {}
        )

        ErrorBubbleView(
            error: ErrorMessage(
                type: .serverError("Internal server error occurred"),
                timestamp: Date()
            ),
            onRetry: {},
            onIgnore: {}
        )
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
