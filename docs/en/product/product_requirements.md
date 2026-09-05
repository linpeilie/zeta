# Product Requirements

Last updated: 2026-08-12

> Translated from [the Chinese original](../../zh/product/product_requirements.md), which is the source of truth if the two diverge.

## 1. Overview

Zeta is a local AI IDE shell built on Flutter Desktop. It targets developers who want to collaborate with a coding agent inside a local project, and provides project directory browsing, file context selection, agent conversations, tool-call display, permission approval and session restore.

The focus of the current version is not a full code editor. It is to validate a desktop workflow built on three things: local project context, an agent thread, and an auditable tool timeline.

## 2. Target users

- **Primary**: developers who work in local repositories day to day and want agent assistance.
- **Secondary**: product and engineering people evaluating agent IDE interaction, thread restore, and the permission approval model.

## 3. Problems being solved

- Developers switch between several local projects and need the agent to know which project and which file is current.
- A running agent produces messages, tool calls and approval requests; the user needs one continuous timeline to follow what happened.
- After the desktop app restarts, it should restore the previously open project, the file tree expansion state, and the most recently used agent thread.

## 4. Product goals

- Provide a stable three-column IDE workbench: Projects, Agent, Files.
- Let the user pick a local project directory and browse its file tree on the right.
- Pass the current project path and the selected file path to the provider as agent context.
- Support creating, resuming and continuing agent threads over Codex CLI app-server, Grok ACP and Claude Code stream-json, degrading the UI according to negotiated capabilities. Cursor has been removed from the product schema and the codebase.
- Display agent messages and tool-call state, and pin permission, question and plan approval above the composer.
- Persist IDE session state so that context is not lost across restarts.

## 5. Current scope

### Shipped

- Desktop Flutter application entry point with a custom window bootstrap.
- Three-column layout: projects and threads on the left, the agent timeline in the middle, the file tree on the right.
- The agent home page merges Projects / Threads and a read-only agent usage summary into one left card. The usage summary is a persistent collapsed strip; expanding it raises a popover with the full breakdown. The title bar's left button controls the whole left column, which becomes an overlay on narrow windows. Left column visibility, width and the selected usage provider are restored after restart; the usage popover is transient UI and is not restored.
- Local directory selection with lazy file tree loading.
- Common large directories are ignored: `.git`, `.dart_tool`, `build`, `node_modules` and similar.
- Zeta's own IDE session, agent provider configuration, appearance settings and the derived usage-statistics index are stored as versioned JSON under Zeta's data directory (a `.zeta` folder inside the platform documents directory). Legacy SharedPreferences data is neither read nor migrated.
- Application logs are written per day under `logs/` in the same directory. Agent CLI configuration and session history stay where they are and are never migrated into Zeta's directory.
- The active built-in providers are Codex CLI, Grok ACP and Claude Code stream-json; Codex remains the default active provider. Cursor appears in no catalog, setting, agent management page, session restore path or runtime composition.
- The agent management page exposes identity, version, account, connection, configuration and redacted diagnostics for the active CLIs.
- Agent events are mapped into a single set of domain models; the UI never binds directly to raw Codex or xAI protocol details.
- Thread listing, history, resume, send, cancel, permissions and dynamic session configuration are all capability-driven. Operations a provider does not support are not shown and never silently succeed.
- The interface supports English and Simplified Chinese. A fresh install follows the first entry in the system's preferred-language list (Traditional Chinese and other unsupported languages fall back to English); existing installs keep Chinese. Changing the language in settings takes effect on the next launch; the running process does not follow system language changes.

### Out of scope for now

- A built-in code editor.
- Reading file contents, in-editor diffs, or a save flow.
- Remote repositories or cloud sync.
- A Zeta-owned login or account system, and any plan purchase, renewal or payment flow. Provider account metadata and plan quota are displayed read-only.
- A full plugin system.
- Mobile support.
- Cursor Cloud Agent, Automations, automatic install/update, and parsing of private local data.

## 6. Key user flows

### Opening a project

1. The user clicks the open-directory button in the Projects panel.
2. The system invokes the platform directory picker.
3. Once a local directory is chosen, the system loads the top level of the file tree.
4. The project is added to the recent projects list and becomes the current workspace.
5. Agent context is updated to the current project path.

### Selecting file context

1. The user expands a directory in the Files panel.
2. The user clicks a file.
3. The system selects that file and sets its path as the agent's current context.
4. The current file name is shown at the top of the Agent panel.

### Sending an agent request

1. The user types a request in the agent composer.
2. The system creates or resumes the agent session for the current project.
3. The system sends the request together with the current file path context to the provider.
4. The agent timeline shows the user message, agent messages and tool cards, and lets the user scroll back through the context.
5. If the provider requests permission, user input or plan approval, a card appears immediately in the fixed interaction area above the composer. Once answered it is removed and never repeated on the timeline.
6. Provider questions and plan approvals use separate cards. Cancellation, timeout, a response from another client, or provider exit must all complete the protocol handshake correctly.

### Switching interface language

1. The user opens Settings → General and selects `English` or `简体中文`.
2. After a successful save, the running interface keeps the language it launched with, and the user is told the change applies after restart.
3. On the next launch, Zeta's own interface, menus, notifications and accessibility labels use the selected language.
4. User input, provider replies, raw tool output, paths, commands and product terms stay as they are. Date, number and relative-time formats do not change with language.

### Restoring a session

1. On launch the app reads the persisted IDE session.
2. Projects and files that no longer exist are filtered out.
3. The system restores the project list, current project, file tree expansion state, selected file, thread cache, plus left column visibility, width and the selected usage provider. The usage popover is not restored.
4. When the user next sends a message or switches thread, the system attempts to resume the corresponding agent session.

## 7. Non-functional requirements

- A failed startup, an unreadable directory, or a failed provider process must never crash the application.
- The file tree must avoid recursively scanning a large repository in one pass.
- Protocol differences between providers must stay inside data-layer implementations; the UI depends only on domain interfaces.
- The default agent approval policy stays conservative and must never auto-authorise a command or a file write.
- Cursor is retired. Zeta does not launch a Cursor provider and does not read, migrate, rewrite or delete Cursor's private configuration, logs, session store or legacy indexes.
- Before a beta release, automated gates and real-CLI smoke tests must run on every declared platform. Missing devices or credentials must never be inferred as a pass.
- The UI must adapt to desktop window resizing without visibly overflowing text or panels.
- Changing interface language must not change provider protocol, prompts or runtime behaviour. User and provider text, paths and commands stay verbatim. Date, number, percentage and relative-time formats, and the product terms `Agent` / `Provider` / `Thread` / `Token`, do not change with language.
- New behaviour needs accompanying unit or widget tests covering at least the highest-risk state transitions.

## 8. Success criteria

- The user can reliably open a local project and browse its file tree.
- The user can start an agent thread against the current project with any enabled, successfully detected provider.
- Agent state, tool calls and approval requests are displayed clearly.
- The app restores the most recent workspace context after a restart.
- The user can choose between English and Simplified Chinese, and gets consistent Zeta-authored copy after restarting.
- `flutter analyze` and the full test suite (6 CI shards plus internal packages) stay green on the main branch.

## 9. Open questions

- Should Zeta ship a built-in text editor, or stay positioned as an agent collaboration panel?
- If Cursor is to be supported again, is there a separate proposal with real protocol fixtures and full cross-platform gate evidence?
- Should the agent read the contents of the selected file, or continue receiving only path context?
- Should permission approvals be persisted as an audit record?
- Do the thread list and project list need search and archiving?
