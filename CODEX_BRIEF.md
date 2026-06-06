# Perch — Codex Implementation Brief

## Operating rules (read first)
1. **One task at a time, in the order below.** Do not start a task until its dependencies are done.
2. **Compile after every task** (`swift build`) and **run its acceptance check** — do not proceed past a failing build or unmet acceptance criterion.
3. **Only edit the files listed for the current task.** Do not create, rename, move, or delete other files; the file layout is fixed.
4. **Never change a pinned public signature, type name, or file path.** Fill `fatalError("unimplemented")` / `TODO` bodies only. Adding *private* helpers inside a listed file is fine; adding new public types, files, or dependencies is not.
5. **If a contract seems missing or contradictory, STOP and surface it** — do not improvise a new protocol, type, method, or design decision.

## Global guardrails
- **Do not re-architect.** The three pipelines (RECEIVE / STORE / RE-VEND), the window model, and the on-disk layout are fixed. See `ARCHITECTURE.md`.
- **Do not add dependencies.** Standard library, `AppKit`, `SwiftUI`, `Combine`, `Foundation`, `UniformTypeIdentifiers`, `QuickLookUI`/`Quartz` only. No SwiftPM packages.
- **Do not alter `DECISIONS.md`, `ARCHITECTURE.md`, `PLAN.md`, or `RISKS.md`.** They are the source of truth, not editable scope.
- **Do not invent missing contracts.** If you think you need a method/type that isn't pinned, stop and ask.
- `Package.swift` pins Swift **language mode 5** and platform **macOS 14**. Do not raise the language mode or add platforms.
- AppKit-touching types are `@MainActor` by decision **B**; the **promise provider/delegate and `FilePromiseMaterializer` callbacks run off the main actor** — respect that boundary (see T7).

## Build / run / test commands (this project)
- Build: `swift build`
- Run the app: `swift run` (the single executable product is `Perch`; `swift run Perch` is equivalent)
- Clean: `swift package clean`
- **There is no XCTest target and you may not add one** (it would expand the file layout). Verify per the acceptance check of each task: `swift build`, `swift run`, and direct manual drag interactions.
- **Sanctioned verification scratch (the ONLY permitted out-of-set edit):** for tasks whose acceptance is "call X and assert Y" with no UI yet (T1, T2, T6), you may *temporarily* invoke the check from `Sources/Perch/main.swift` (guarded, e.g. behind a `// SCRATCH` marker or a `--selftest` arg), run `swift run`, confirm, then **revert that scratch before the task is considered done**. The scratch is never part of the deliverable.

---

# Tasks (dependency order)

## T0.1 — Package + entry + empty panel
**Context:** Stand up a runnable AppKit accessory app (no Dock icon, no menu bar) whose only behavior is to show a single empty floating panel. This is the foundation everything else hangs off.

**Files (only):** `Package.swift`, `Sources/Perch/main.swift`, `Sources/Perch/App/AppDelegate.swift`, `Sources/Perch/App/ShelfController.swift`, `Sources/Perch/Windows/ShelfPanel.swift`.

**Locked signatures:**
- `final class AppDelegate: NSObject, NSApplicationDelegate` — `func applicationDidFinishLaunching(_ notification: Notification)`
- `final class ShelfPanel: NSPanel` — `init(contentRect: NSRect)`, `required init?(coder: NSCoder)`, `override var canBecomeKey: Bool { false }`
- `final class ShelfController` (`@MainActor`) — `init() throws`, `func start()` (also already conforms to `ShelfDropHandling`, `EdgeStripDelegate`; leave those methods as `fatalError` until their tasks)

**Scope note:** `ShelfController` is built incrementally. In T0.1 it must only create and show a `ShelfPanel` — do **not** call into store/snapshotter/window-controller (those bodies are still `fatalError`). Later tasks (T3, T4, T7, T11) extend it.

> **DO NOT REGRESS (window level):** `ShelfPanel` must use window `level = .floating` — **NOT** `.statusBar`, `.mainMenu`, or any level above the menu bar. A full-height right-edge panel must sit *below* the menu bar / notch (Decision L2). If `.floating` is too low for a later full-screen case, the fix is to *inset the panel below the menu bar*, never to raise the level above it. Also set `.nonactivatingPanel` and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

**Acceptance check:** `swift build` is clean; `swift run` launches with no Dock icon and shows one non-activating panel that appears on all Spaces, does not take key focus, and does not cover the menu bar / notch.

**Deps:** none.

---

## T1 — Data model + holding directory + persistence
**Context:** Implement the in-memory item store and its on-disk backing under `~/Library/Application Support/Perch/`. No drag/drop yet — just the model + JSON round-trip. See `ARCHITECTURE.md` §4 for the exact on-disk layout.

**Files (only):** `Sources/Perch/Model/StoredItem.swift`, `Sources/Perch/Model/ItemStore.swift`, `Sources/Perch/Storage/HoldingDirectory.swift`.

**Locked signatures:**
- `struct RepRecord: Codable, Equatable { let typeIdentifier: String; let fileName: String; let isPromisePlaceholder: Bool }`
- `struct ItemMetadata: Codable, Equatable { let id: UUID; let createdAt: Date; var title: String; var representations: [RepRecord]; var backingFileNames: [String]; var primaryFileType: String? }`
- `final class StoredItem: Identifiable` (`@MainActor`) — `init(metadata: ItemMetadata, directoryURL: URL)`, `nonisolated var id: UUID`, `func data(forType: NSPasteboard.PasteboardType) -> Data?`, `func backingFileURLs() -> [URL]`, `func iconImage() -> NSImage`
- `final class ItemStore: ObservableObject` (`@MainActor`) — `@Published private(set) var items: [StoredItem]`, `init(holding: HoldingDirectory)`, `func load() throws`, `func insert(_ item: StoredItem, at index: Int?)`, `func remove(_ item: StoredItem)`, `func newItemDirectory() -> (id: UUID, url: URL)`
- `struct HoldingDirectory { let root: URL; static func standard() throws -> HoldingDirectory; var itemsDir: URL; var indexFile: URL; func itemDir(_ id: UUID) -> URL }`

**Acceptance check (use the sanctioned scratch):** a code path creates `~/Library/Application Support/Perch/items/<uuid>/{reps,files}` + `meta.json`, writes `index.json`, then `ItemStore(holding:).load()` on a fresh instance returns the same items in `index.json` order. Confirm the directories/files exist on disk.

**Deps:** T0.1.

---

## T2 — Snapshot (data + real files only)
**Context:** Implement the STORE step that captures everything off a pasteboard at receive time. Promises are *recorded* now but materialized later (T6/T7).

**Files (only):** `Sources/Perch/Storage/PasteboardSnapshotter.swift`.

**Locked signature:**
- `struct PasteboardSnapshotter` (`@MainActor`) — `let holding: HoldingDirectory`; `func snapshot(_ pasteboard: NSPasteboard, into store: ItemStore) throws -> (item: StoredItem, pendingPromises: [NSFilePromiseReceiver])`

**Behavior:** for each `NSPasteboardItem`, write every `data(forType:)` to `reps/rep-N.dat` and record a `RepRecord`; copy `public.file-url` targets into `files/`; record promise-only types with `isPromisePlaceholder = true` (collect their `NSFilePromiseReceiver`s into `pendingPromises`, do not fulfill them here); write `meta.json`.

**Acceptance check (synthetic, no UI):** build an `NSPasteboard(name: .init("perch.test"))`, clear it, `setString`/`setData` a couple of representations plus a `public.file-url` pointing at a temp file, call `snapshot(_:into:)`, and assert: one non-empty `rep-N.dat` per representation, the referenced file copied into `files/`, and a well-formed `meta.json`. (Real drag receipt is T3.)

**Deps:** T1.

---

## T3 — Receive view wired into the panel
**Context:** Make the panel an actual drop target that routes incoming drags into T2's snapshotter and T1's store.

**Files (only):** `Sources/Perch/Receive/ShelfDropView.swift`; edits to `Sources/Perch/App/ShelfController.swift` and `Sources/Perch/App/AppDelegate.swift`.

**Locked signatures:**
- `protocol ShelfDropHandling: AnyObject` (`@MainActor`) — `func handleDrop(_ pasteboard: NSPasteboard) -> Bool`
- `final class ShelfDropView: NSView` — `weak var dropHandler: ShelfDropHandling?`, `static let acceptedTypes: [NSPasteboard.PasteboardType]`, `override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation`, `override func performDragOperation(_ sender: NSDraggingInfo) -> Bool`
- `ShelfController` now implements `handleDrop(_:)` (it already declares conformance to `ShelfDropHandling`).

**Behavior:** populate `acceptedTypes` (file URL, file promise, string, RTF, TIFF, URL, HTML); `registerForDraggedTypes`; `performDragOperation` calls `dropHandler?.handleDrop`, which snapshots into the store. Set the panel's content to the `ShelfDropView` (or make it the contentView), and wire `dropHandler` to the `ShelfController`.

**Acceptance check:** `swift run`, drag a file or selected text from another app onto the panel → `store.items.count` increases (log it). Master files land under the item's `files/`.

**Deps:** T2.

---

## T4 — SwiftUI item list hosted in the panel
**Context:** Render the stored items as a live list inside the panel using SwiftUI hosted via `NSHostingView`. SwiftUI is for *rendering only*.

**Files (only):** `Sources/Perch/UI/ShelfContentView.swift`, `Sources/Perch/UI/ItemRowView.swift`; edit `Sources/Perch/App/ShelfController.swift`.

**Locked signatures:**
- `struct ShelfContentView: View { @ObservedObject var store: ItemStore }`
- `struct ItemRowView: View { let item: StoredItem }`

**Behavior:** `ItemRowView` shows `item.iconImage()` + `item.metadata.title`; `ShelfContentView` lists `store.items` in order; host it in the panel via `NSHostingView`. Live-updates because `ItemStore` is `@Published`.

**Acceptance check:** `swift run`, drop items → rows appear immediately; removing an item from the store updates the UI.

**Deps:** T3.

---

## T5 — Re-vend (basic: file URL + concrete data; `.copy`-only; AppKit-initiated)
**Context:** Let the user drag a row back *out* of the shelf. This is the first half of RE-VEND — concrete file URL + stored data, no promises yet (promises come in T8/T9). The drag is started from AppKit, and the operation mask is locked to copy.

**Files (only):** `Sources/Perch/Vend/ItemDragSource.swift`, `Sources/Perch/UI/ShelfHostView.swift`.

**Locked signatures:**
- `final class ItemDragSource: NSObject, NSDraggingSource` (`@MainActor`) — `init(item: StoredItem)`, `func beginDrag(from view: NSView, event: NSEvent) -> NSDraggingSession`, `func draggingItem() -> NSDraggingItem`, `func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation`
- `final class ShelfHostView: NSView` — `init(store: ItemStore)`, `required init?(coder: NSCoder)`, `override func mouseDragged(with event: NSEvent)`

> **DO NOT REGRESS (copy-only, real dragging source):**
> - `ItemDragSource` is a **concrete `NSDraggingSource` class** that is passed as the `source:` to `beginDraggingSession(with:event:source:)` and is **retained by `ShelfHostView` for the drag's duration**. It is **not** a struct with a static method — a struct cannot serve as the drag source, and the operation mask must live on a real source object.
> - `draggingSession(_:sourceOperationMaskFor:)` must return **`.copy`** for file-backed items in **both** `.withinApplication` and `.outsideApplication` contexts, so no destination (Finder included) can move/relocate the holding-dir master.
> - **AppKit is the primary drag-initiation path:** `ShelfHostView.mouseDragged(with:)` identifies the hit row, creates + retains an `ItemDragSource`, and calls `beginDrag`. Do **not** route drag-initiation through a SwiftUI gesture; the old `ItemRowDragModifier` was deliberately removed.

**Acceptance check:** `swift run`; drag a row to the Desktop → a file is copied out **and the master under the item's `files/` still exists** (it must be copy, never move); drag a text item into TextEdit → the text appears. Confirm the drag starts from `mouseDragged`, not a SwiftUI gesture.

**Deps:** T4.

> **M1 GATE:** Finder file → panel row → Desktop copy (master preserved); and TextEdit selection → panel → TextEdit. No promises, no edge strip.

---

## T6 — File promise materializer
**Context:** Implement the helper that fulfills inbound file promises (`NSFilePromiseReceiver`) into a target directory. Pure mechanism; wiring is T7.

**Files (only):** `Sources/Perch/Storage/FilePromiseMaterializer.swift`.

**Locked signature:**
- `final class FilePromiseMaterializer` (`@MainActor`) — `let operationQueue: OperationQueue`, `init()`, `func materialize(_ receivers: [NSFilePromiseReceiver], into filesDir: URL, completion: @escaping ([URL]) -> Void)`

> **Note (carried into T7):** `completion` fires on `operationQueue` — **off the main actor**. Keep it that way; do not silently make it main-actor here.

**Acceptance check (scratch):** a standalone call with one or more receivers writes the promised files into `filesDir` and calls `completion` with their URLs. Confirm files exist on disk.

**Deps:** T5.

---

## T7 — Wire promise receipt into snapshot/store
**Context:** Connect T6 so that promise-only drags (e.g. from Photos) produce real files and a row, not just a placeholder.

**Files (only):** edits to `Sources/Perch/Storage/PasteboardSnapshotter.swift`, `Sources/Perch/Receive/ShelfDropView.swift`, `Sources/Perch/App/ShelfController.swift`.

**Behavior:** when a drop carries promise receivers (`pendingPromises` from T2), drive them through `FilePromiseMaterializer.materialize(...)` into the item's `files/`, then update the item's metadata/backing files and the store.

> **DO NOT REGRESS (main-actor hop):** `FilePromiseMaterializer`'s completion fires on its `OperationQueue` (off-main). Before mutating `ItemStore` (which is `@MainActor` + `@Published`), you **must hop to the main actor** (e.g. `Task { @MainActor in … }` or `DispatchQueue.main.async`). An off-main `@Published` mutation is a defect, not a warning to defer.

**Acceptance check:** `swift run`, drag an image from **Photos** onto the panel → a real file appears under `files/` and a row appears. Assert the store mutation runs on the main thread (`Thread.isMainThread` at the mutation site, or run with the Main Thread Checker enabled and see no violation).

**Deps:** T6.

---

## T8 — Promise + lazy writer
**Context:** Build the single object that vends a stored item *out* with a file promise plus the item's generic representations lazily. See `ARCHITECTURE.md` §2 RE-VEND and Decision F.

**Files (only):** `Sources/Perch/Vend/StoredItemDragWriter.swift` (provider + delegate, both already present).

**Locked signatures:**
- `final class StoredItemDragWriter: NSFilePromiseProvider` — `convenience init(item: StoredItem)`, `override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType]`, `override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions`, `override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any?`
- `final class StoredItemDragWriterDelegate: NSObject, NSFilePromiseProviderDelegate` — `init(item: StoredItem)`, `func filePromiseProvider(_:, fileNameForType:) -> String`, `func filePromiseProvider(_:, writePromiseTo:, completionHandler:)`, `func operationQueue(for:) -> OperationQueue`

**Note:** these types are intentionally **not** `@MainActor` (promise writes run on the delegate's `operationQueue`). Do not add `@MainActor`.

**Acceptance check (scratch):** the writer reports the expected `writableTypes` (file + the item's stored generic types), and the delegate writes the promised file (a fresh copy) from the item's `files/` on demand. Confirm the written file matches the master byte-for-byte.

**Deps:** T7.

---

## T9 — Single-item multi-representation drag (promise-preferred, copy-only)
**Context:** Swap T5's basic re-vend so the drag uses `StoredItemDragWriter`, making the file **promise** the primary delivery path.

**Files (only):** edit `Sources/Perch/Vend/ItemDragSource.swift`.

> **DO NOT REGRESS (promise-preferred + copy-only):**
> - Build the single `NSDraggingItem` around `StoredItemDragWriter` so file delivery **prefers the promise** (it writes a fresh copy and never exposes the holding-dir master). Offer the concrete holding-dir file URL **only** as an instant-local convenience — never as a moveable handle to the master.
> - Keep `draggingSession(_:sourceOperationMaskFor:)` returning **`.copy`** for file items (from T5). The master under `files/` must survive every drag-out.

**Acceptance check:** drag a row into a promise-only destination (e.g. Mail compose) → the file materializes via the promise; drag into a local target → instant via the convenience URL; a text item still drops its text. **After each drag-out, confirm the master under `files/` still exists.**

**Deps:** T8.

> **M3 GATE:** Promises work in **both** directions — Photos-in (T7) and Mail-out (T9).

---

## T10 — Edge strip window
**Context:** Add the always-present thin window at the right screen edge that detects an incoming drag and (later, T11) reveals the shelf. The strip itself is a *trigger only*.

**Files (only):** `Sources/Perch/Windows/EdgeStripWindow.swift`.

**Locked signatures:**
- `protocol EdgeStripDelegate: AnyObject` (`@MainActor`) — `func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow)`
- `final class EdgeStripWindow: NSPanel` — `static let stripWidth: CGFloat` (= 4), `weak var stripDelegate: EdgeStripDelegate?`, `init(screen: NSScreen)`, `required init?(coder: NSCoder)`

> **DO NOT REGRESS (geometry / event policy):**
> - The strip is **`stripWidth` (4 pt) wide**, full screen height, pinned to the right edge, transparent.
> - `ignoresMouseEvents = false` — **required** to receive `draggingEntered`. (Accepted tradeoff: it also captures idle clicks in that ~4 pt region. Do not "fix" this by making it click-through unless RISKS §7's verification says drags still route to an `ignoresMouseEvents = true` window.)
> - The strip **never accepts the drop**: `draggingEntered` only notifies the delegate (reveal). The real drop target is the panel's `ShelfDropView`.

**Acceptance check:** `swift run`, drag anything to the right edge → `edgeStripDidReceiveDrag` fires (log it). Confirm the strip is ≤ 4 pt wide and full-height.

**Deps:** T5.

---

## T11 — Reveal/hide controller
**Context:** Make the edge strip actually reveal the shelf, then auto-hide it, and remember the panel's frame.

**Files (only):** `Sources/Perch/Windows/ShelfWindowController.swift`; edit `Sources/Perch/App/ShelfController.swift`.

**Locked signatures:**
- `final class ShelfWindowController` (`@MainActor`) — `let panel: ShelfPanel`, `init(panel: ShelfPanel)`, `func reveal(animated: Bool)`, `func hide(animated: Bool)`, `func restorePersistedFrame()`, `func persistFrame()`
- `ShelfController` now implements `edgeStripDidReceiveDrag(_:)` (conformance already declared).

**Behavior:** strip drag → `ShelfController.edgeStripDidReceiveDrag` → `ShelfWindowController.reveal` (slide in from the edge); auto-hide after a drop or timeout; persist/restore the frame.

**Acceptance check:** `swift run`, drag to the edge → shelf slides in → drop lands on it → shelf hides. Frame restores across relaunch.

**Deps:** T10.

---

## T12 — Item delete + clear-all + Quick Look
**Context:** Add the ability to remove items and preview them. Because the panel never becomes key, these controls are **AppKit on the host view**, not SwiftUI controls.

**Files (only):** edit `Sources/Perch/UI/ShelfHostView.swift`, `Sources/Perch/Model/ItemStore.swift`, `Sources/Perch/UI/ItemRowView.swift`.

**Contract addition (sanctioned, listed here):** add `func clearAll()` to `ItemStore`. This is the only new public method permitted in this task; do not add others. `remove(_:)` already exists from T1.

> **DO NOT REGRESS (AppKit-primary controls):** delete / clear-all / Quick Look are driven via **AppKit on `ShelfHostView`** (context menu / key handling; Quick Look via `QLPreviewPanel`). Do **not** rely on SwiftUI buttons/gestures for these — a non-key panel does not reliably deliver them. `ItemRowView` may show purely *visual* affordances only.

**Behavior:** delete removes the row, deletes its `items/<uuid>/` directory, updates the store; clear-all empties the shelf and its on-disk items; Quick Look previews the selected item.

**Acceptance check:** `swift run`; right-click / key-driven delete on the host view removes a row and its `items/<uuid>/` dir; clear-all empties the shelf; Quick Look opens a preview — all while the panel is non-key.

**Deps:** T4, T5.

---

## T13 — (Optional) global mouse-monitor pre-warm
**Context:** Optional enhancement: a global `NSEvent` mouse monitor to pre-warm/expand the strip. Permission-sensitive — **read `RISKS.md` §1 first.**

**Files (only):** new `Sources/Perch/App/MouseMonitor.swift`. This is the one task that adds a file; no public signature is pinned for it yet. **Before writing it, surface a proposed public interface for approval** rather than inventing one silently.

> **Guardrail:** monitor **mouse events only** (never key events — those require Accessibility/TCC). Gate the whole feature behind a flag, default off. If a TCC prompt appears at runtime, stop and surface it (RISKS §1).

**Acceptance check:** with the flag on, the monitor fires on a global mouse-drag with no TCC prompt; with the flag off, behavior is identical to pre-T13.

**Deps:** T11.

---

## Kickoff
> Start with **T0.1 — Package + entry + empty panel**. Touch only `Package.swift`, `Sources/Perch/main.swift`, `Sources/Perch/App/AppDelegate.swift`, `Sources/Perch/App/ShelfController.swift`, `Sources/Perch/Windows/ShelfPanel.swift`. Fill the stub bodies without changing any pinned signature, keep `ShelfPanel` at `level = .floating`, then `swift build` and `swift run` to confirm a non-activating, all-Spaces panel that does not cover the menu bar. Stop and report before moving to T1.
