# PRD: CoreData Model V3 Migration

## Overview

This document describes the CoreData model migration from v1 (base model) to v3, which was implemented to support CloudKit synchronization and improve message ordering performance.

## Background

The original CoreData model used an **ordered relationship** (`ordered="YES"`) for the `ChatEntity.messages` relationship. This approach had two limitations:

1. **CloudKit Incompatibility**: CloudKit does not support ordered relationships
2. **Performance**: Ordered relationships can be slower for large datasets

## Changes Summary

### Model Changes (v1 → v3)

| Entity | Attribute/Relationship | v1 (Base) | v3 |
|--------|------------------------|-----------|-----|
| ChatEntity | messages | `ordered="YES"` | Unordered (no `ordered` attribute) |
| ChatEntity | lastSequence | Not present | `Int64`, non-optional, default: 0 |
| MessageEntity | sequence | Not present | `Int64`, non-optional, default: 0 |
| ChatEntity | apiService | No inverse | Has inverse: `chats` |
| ChatEntity | persona | No inverse | Has inverse: `chats` |
| APIServiceEntity | chats | Not present | To-many relationship (inverse of apiService) |
| APIServiceEntity | defaultPersona | No inverse | Has inverse: `apiServicesAsDefault` |
| PersonaEntity | chats | Not present | To-many relationship (inverse of persona) |
| PersonaEntity | apiServicesAsDefault | Not present | To-many relationship (inverse of defaultPersona) |

### Key Technical Decisions

#### 1. Custom Mapping Model Required

The change from `ordered="YES"` to unordered relationship is **not supported by lightweight migration**. This required creating a custom mapping model:

- **File**: `V1toV3.xcmappingmodel` (created via Xcode)
- **Source Model**: `macaiDataModel.xcdatamodel`
- **Destination Model**: `macaiDataModel 3.xcdatamodel`

#### 2. Migration Configuration

```swift
// In PersistenceController.init()
for description in container.persistentStoreDescriptions {
    description.shouldMigrateStoreAutomatically = true
    description.shouldInferMappingModelAutomatically = false  // Use custom mapping model
}
```

#### 3. Message Ordering Strategy

Instead of relying on CoreData's ordered relationship, messages are now ordered using:

1. **`sequence` attribute**: Each message gets a sequence number within its chat
2. **`lastSequence` attribute**: Each chat tracks the last assigned sequence number
3. **Fetch with sort descriptors**: Messages are fetched and sorted by sequence

```swift
// In ChatEntity.messagesArray
let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
fetchRequest.predicate = NSPredicate(format: "chat == %@", self)
fetchRequest.sortDescriptors = [
    NSSortDescriptor(keyPath: \MessageEntity.sequence, ascending: true),
    NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: true),
]
```

#### 4. Sequence Backfill

The `DatabasePatcher.backfillMessageSequencesIfNeeded()` function populates sequence values for existing messages after migration, sorting by timestamp.

## File Structure

```
macai/Store/
├── macaiDataModel.xcdatamodeld/
│   ├── .xccurrentversion          # Points to "macaiDataModel 3.xcdatamodel"
│   ├── macaiDataModel.xcdatamodel # v1 - Base model (ordered messages)
│   ├── macaiDataModel 2.xcdatamodel # v2 - Intermediate (unused for this migration)
│   └── macaiDataModel 3.xcdatamodel # v3 - Target model (unordered + sequence)
├── V1toV3.xcmappingmodel          # Custom mapping model
└── ChatStore.swift
```

## Backup Strategy

### Automatic Pre-Migration Backup

Before migration, the app automatically creates a backup of the CoreData files:

- **Location**: `~/Library/Application Support/<bundleID>/Backups/Before-macaiDataModel 3-<timestamp>/`
- **Files backed up**: `.sqlite`, `.sqlite-wal`, `.sqlite-shm`
- **One-time flag**: `CoreDataBackupBeforeV3Completed` in UserDefaults

### Backup Discovery

Backups are discoverable in Settings → Backup & Restore, implemented via `DatabaseBackupManager.discoverBackups()`.

## Migration Flow

```
App Launch
    │
    ▼
CoreDataBackupManager.backupBeforeV3IfNeeded()
    │ (Creates backup if flag not set)
    ▼
container.loadPersistentStores()
    │ (Uses V1toV3.xcmappingmodel for migration)
    ▼
DatabasePatcher.applyPatches()
    │
    ├── patchMissingIDs()
    ├── backfillMessageSequencesIfNeeded()
    └── (other patches...)
    │
    ▼
App Ready
```

## Testing Checklist

- [ ] Fresh install works correctly
- [ ] Migration from v1 database preserves all chats and messages
- [ ] Messages appear in correct order after migration
- [ ] Backup is created before migration
- [ ] Backup appears in Settings → Backup & Restore
- [ ] CloudKit sync works with new model (if enabled)

## Troubleshooting

### Migration Fails / Empty App After Update

1. Check console for "Failed to load persistent store" errors
2. Verify `.xccurrentversion` points to `macaiDataModel 3.xcdatamodel`
3. Ensure `V1toV3.xcmappingmodel` is included in the target
4. Verify `shouldInferMappingModelAutomatically = false`

### Backup Not Created

1. Check if `CoreDataBackupBeforeV3Completed` flag is already set:
   ```bash
   defaults read com.notfullin.macai CoreDataBackupBeforeV3Completed
   ```
2. Reset flag to test:
   ```bash
   defaults delete com.notfullin.macai CoreDataBackupBeforeV3Completed
   ```

### Messages Out of Order

1. Check if `backfillMessageSequencesIfNeeded()` ran successfully
2. Verify `MessageSequenceBackfillCompleted` flag in UserDefaults
3. Reset and re-run if needed:
   ```bash
   defaults delete com.notfullin.macai MessageSequenceBackfillCompleted
   ```

## Related Files

- `macai/macaiApp.swift` - PersistenceController, CoreDataBackupManager
- `macai/Models/Models.swift` - ChatEntity, MessageEntity with sequence logic
- `macai/Utilities/DatabasePatcher.swift` - Migration patches
- `macai/UI/Preferences/TabBackupRestoreView.swift` - Backup UI
