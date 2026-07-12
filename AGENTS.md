# Draft-Save Crash Fix (Core Data)

## Summary
We fixed EXC_BAD_ACCESS / Core Data crashes tied to draft saving and iCloud sync. The primary issue was a Core Data attribute named **`newMessage`**, which conflicts with Objective‑C “new*” naming rules and can crash during Swift/Obj‑C bridging. Secondary fixes ensured Core Data access stays on the correct queue.

## Root Cause
1) **Core Data attribute named `newMessage`**. Properties starting with `new*` are treated specially by Objective‑C (“Create Rule”). Core Data’s dynamic accessors and Swift bridging can crash when a model attribute uses a `new*` name.
2) Crashes appeared during SwiftUI updates and iCloud sync (forwarding / bridging failures such as `___forwarding___` + Swift string bridging).
3) Some Core Data fetches were performed off the context’s queue (e.g., in async tasks), triggering `_PFAssertSafeMultiThreadedAccess_impl`.

## Fix Strategy
### A) Rename the Core Data draft field
`ChatEntity.newMessage` → `ChatEntity.draftMessage` (with `renamingIdentifier="newMessage"`).
This avoids Objective‑C “new*” naming collisions while preserving data during migration and sync.

### B) Isolate draft saves in a background context
Drafts are saved in a private queue context with a unique `transactionAuthor`:
- `AppConstants.draftTransactionAuthor = "Drafts"`
- Draft saves use this context only.

### C) Store only IDs in drafts
Drafts store message text + attachment **IDs**, not entire objects. This keeps draft saves lightweight and avoids merging attachment data into the UI context.

### D) Fix Core Data queue violations
Every Core Data fetch from background threads now uses `perform` / `performAndWait` on the correct context.

## Key Code Changes
### Draft handling
- `macai/UI/Chat/ChatDraftManager.swift`
  - Uses private background context for draft saves.
  - Drafts store `draftImageIDs` / `draftFileIDs` only.
  - Draft restore fetches IDs and loads attachments by ID.
  - Draft message reads use `draftMessage` and detach the Swift string from Core Data objects.

- `macai/Configuration/AppConstants.swift`
  - Added `draftTransactionAuthor`.

### Data model rename
- `macai/Store/macaiDataModel.xcdatamodeld/.../contents`
  - `newMessage` renamed to `draftMessage` with `renamingIdentifier="newMessage"`.

### Core Data save reliability
- `macai/Utilities/Extensions.swift`
  - `saveWithRetryOnQueue` ensures save happens on context queue.

### Thread-safety fixes (Core Data fetches)
These now use `performAndWait` on `viewContext`:
- `macai/Utilities/APIHandlers/OpenAIHandlerBase.swift`
- `macai/Utilities/APIHandlers/GeminiHandler.swift`
- `macai/Utilities/MessageParser.swift`

These now fetch entity data **from the entity’s context queue** before using it on background threads:
- `macai/Models/ImageAttachment.swift`
- `macai/Models/DocumentAttachment.swift`

### Attachment persistence for drafts
Attachments added via Photos picker or drag/drop are persisted immediately so the draft can restore them later:
- `macai/UI/Chat/BottomContainer/MessageInputView.swift`

### PDF attachments (general)
- PDFs are represented in message text as `<file-uuid>...</file-uuid>` placeholders and stored as `DocumentEntity` records with `fileData`, `filename`, and `mimeType`.
- The UI exposes “Add PDF” and PDF previews when `pdfUploadsAllowed` is enabled for the selected API service.
- Drafts store only PDF IDs (`draftFileIDs`) and restore PDFs by ID.

### OpenAI PDF attachments
OpenAI Responses models accept PDFs via `input_file` items (`file_data` data URL + `filename`) in the request payload:
- `macai/Utilities/APIHandlers/OpenAIResponsesHandler.swift`
- `macai/Utilities/APIHandlers/OpenAIHandlerBase.swift`
- `macai/UI/Chat/ChatLogicHandler.swift`
- `macai/UI/Chat/ChatView.swift`

### Gemini PDF attachments
Gemini now supports PDF attachments by translating `<file-uuid>` placeholders into `inlineData` parts (base64 + mime type), and PDF uploads are enabled in Gemini defaults/templates:
- `macai/Utilities/APIHandlers/GeminiHandler.swift`
- `macai/Configuration/AppConstants.swift`
- `macai/Utilities/APIServiceTemplateProvider.swift`
- `macai/Configuration/APIServiceTemplates.json`
- Existing Gemini services are backfilled via `DatabasePatcher.patchGeminiPdfUploadsForAPIServices` (flag: `geminiPdfUploadsPatchCompletedKey`).

## Context Primer (Short Version)
- A **context** is a Core Data workspace with its own thread/queue.
- Objects from a context must only be accessed on that context’s queue.
- The **viewContext** is tied to the main thread (SwiftUI).
- Background contexts are used for async work (e.g., draft autosaves).
- If you read or write objects on the wrong queue, Core Data throws `_PFAssertSafeMultiThreadedAccess_impl`.

## Testing Checklist
1) Type text → switch chat → switch back (draft restores, no crash).
2) Add image/PDF → switch chat → switch back (draft restores, no crash).
3) Send message with attachments (no crash).
4) Add attachment via drag/drop and Photos picker (draft restores).

## Notes / Caveats
- Draft data is restored explicitly via `ChatDraftManager.draftSnapshot(...)` during `ChatView` init.
- If you introduce new Core Data fetches that run off-main, wrap them in `context.perform {}` or `performAndWait {}`.
