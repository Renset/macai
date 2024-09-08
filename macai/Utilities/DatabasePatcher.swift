//
//  DatabasePatcher.swift
//  macai
//
//  Created by Renat Notfullin on 08.09.2024.
//

import Foundation
import CoreData
import SwiftUI

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonasIfNeeded(context: context)
    }
    
    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if force || !defaults.bool(forKey: AppConstants.defaultPersonasFlag) {
            for persona in AppConstants.PersonaPresets.allPersonas {
                let newPersona = PersonaEntity(context: context)
                newPersona.name = persona.name
                newPersona.color = persona.color
                newPersona.systemMessage = persona.message
                newPersona.addedDate = Date()
            }
            
            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
                print("Default personas added successfully")
            } catch {
                print("Failed to add default personas: \(error)")
            }
        }
    }
}
