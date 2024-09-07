//
//  DatabasePatcher.swift
//  macai
//
//  Created by Renat Notfullin on 08.09.2024.
//

import Foundation
import CoreData

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonaIfNeeded(context: context)
    }
    
    private static func addDefaultPersonaIfNeeded(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: AppConstants.defaultPersonaFlag) {
            let defaultPersona = PersonaEntity(context: context)
            defaultPersona.name = AppConstants.defaultPersonaName
            defaultPersona.color = AppConstants.defaultPersonaColor
            defaultPersona.systemMessage = AppConstants.chatGptSystemMessage
            
            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonaFlag)
                print("Default persona added successfully")
            } catch {
                print("Failed to add default persona: \(error)")
            }
        }
    }
}
