# Clipps — Windows Clipboard Manager (Spec)

> Source: the user's request of 2026-11-03, copied verbatim. The plan at
> `docs/superpowers/plans/2026-11-03-clipboard-manager.md` implements it.

Develop a native Windows desktop application using Flutter/Dart that functions as a persistent, history-logging clipboard manager. The core function is to capture and store copied text snippets indefinitely until explicitly deleted by the user.

## 💻 Technical Specifications

- Platform Target: Windows Desktop (using Flutter's desktop capabilities).
- Technology Stack: Dart/Flutter.
- Persistence Layer: SQLite Database (sqflite package) for reliable, structured storage of all clip entries.
- Core Requirement: Must function as a background service to monitor the OS clipboard in real-time and capture changes automatically.

## 🧠 Functional Requirements (What it must do)

- Automatic Monitoring: The application must listen for clipboard change events at the Windows OS level (this is the most complex part, likely requiring Flutter Platform Channels/WinAPI integration).
- Clip Capture: When a new clip is detected, it must be:
  - Read into memory.
  - Timestamped (recording when it was clipped).
  - Saved to the local SQLite database.
- History Display: The main UI must display a list of all historical clips, ordered by most recently copied first.
- Manual Input: Users must have the ability to manually paste content into the app and trigger a "Save Clip" action (a good fallback/testing mechanism).
- CRUD Operations:
  - C (Create): Automatically capture or manually save a clip.
  - R (Read): Display history list, allow searching/filtering clips by text content or date range.
  - U (Update): N/A for this scope.
  - D (Delete): Allow selecting and deleting one or multiple historical clips permanently from the database.

## 🏛️ Architectural Structure (How it should be organized)

We will follow a Clean Architecture approach:

| Layer | Responsibility | Key Files/Packages |
|---|---|---|
| UI/Presentation | Displaying data, handling user interactions. | lib/screens/*, main.dart |
| Logic/State | Managing the application state (e.g., what clips are currently loaded; what is being filtered). | lib/providers/clipboard_provider.dart (Using State Management) |
| Data/Repository | Interacting with the database, fetching models, and implementing business logic rules. | lib/database/db_helper.dart, lib/models/clipboard_model.dart |
| OS Integration | Handling platform-specific APIs (e.g., reading the Windows clipboard). | flutter_platform_channel or dedicated native code hooks. |

## 🚧 Next Steps for Development

1. Implement the ClipboardModel and set up the SQLite connection in db_helper.dart.
2. Build the core logic service to perform CRUD operations against the database.
3. Develop the UI to display history and allow deletion/search.
4. Tackle the OS hook: Implement the background clipboard listener using Platform Channels targeting Windows API calls.
