//
//  Extensions.swift
//  macai
//
//  Created by Renat Notfullin on 27.05.2023.
//

import CoreData

extension NSManagedObjectContext {
    func saveWithRetry(attempts: Int) {
        do {
            try self.save()
        } catch {
            print("Core Data save failed: \(error)")
            
            self.rollback()
            
            if attempts > 0 {
                print("Retrying save operation...")
                self.saveWithRetry(attempts: attempts - 1)
            } else {
                print("Failed to save after multiple attempts")
            }
        }
    }
}
