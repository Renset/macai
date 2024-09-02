//
//  APIServiceConfig.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import Foundation

struct APIServiceConfig: APIServiceConfiguration, Codable {
    var name: String
    var apiUrl: URL
    var apiKey: String
    var model: String
}
