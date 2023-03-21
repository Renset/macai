//
//  ChatStore.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import Foundation
import SwiftUI

class ChatStore: ObservableObject {
  @Published var chats: [Chat] = []

  private static func fileURL() throws -> URL {

    try FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    )

    .appendingPathComponent("chats.data")

  }

  static func load(completion: @escaping (Result<[Chat], Error>) -> Void) {

    DispatchQueue.global(qos: .background).async {

      do {

        let fileURL = try fileURL()

        guard let file = try? FileHandle(forReadingFrom: fileURL) else {
          DispatchQueue.main.async {
            completion(.success([]))
          }

          return
        }

        let chats = try JSONDecoder().decode([Chat].self, from: file.availableData)

        DispatchQueue.main.async {
          completion(.success(chats))
        }

      } catch {

        DispatchQueue.main.async {
          completion(.failure(error))
        }

      }

    }

  }

  static func save(chats: [Chat], completion: @escaping (Result<Int, Error>) -> Void) {

    DispatchQueue.global(qos: .background).async {

      do {

        let data = try JSONEncoder().encode(chats)
        let outfile = try fileURL()
        try data.write(to: outfile)

        DispatchQueue.main.async {
          completion(.success(chats.count))
        }

      } catch {

        DispatchQueue.main.async {
          completion(.failure(error))
        }

      }

    }

  }
}
