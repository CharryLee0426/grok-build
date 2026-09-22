# Grok Desktop for macOS

A native SwiftUI client for the Grok Build harness in this repository. It brings a
project sidebar, persistent tasks, a focused conversation view, and a changes
inspector to the existing agent runtime. The app launches `grok agent stdio` and
communicates through ACP v1; the harness continues to run tools, manage sandboxing,
and load provider credentials and configuration.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 15 or later, or compatible Command Line Tools with Swift 5.9+ and the
  macOS 14+ SDK. Run `xcode-select --install` if the tools are not installed.
- A Grok CLI with `agent stdio` support, preferably built from this checkout.

The desktop package has no external Swift dependencies and uses Apple's system
frameworks. Building the Rust harness has its own requirements, documented in the
[repository README](../../README.md#building-from-source).

## Build and launch

Run these commands from the repository root:

```sh
# Build the harness, or use an existing compatible Grok installation.
cargo build -p xai-grok-pager-bin --release

# Build a release .app and embed target/release/xai-grok-pager when available.
./desktop/macOS/scripts/build-app.sh
open "desktop/macOS/dist/Grok Desktop.app"
```

You can move the generated app into `/Applications`. The packaging script embeds
the release harness as `Contents/Resources/grok`, signs that executable, and then
signs the app. To bundle a different executable:

```sh
GROK_BINARY="/absolute/path/to/grok" ./desktop/macOS/scripts/build-app.sh
```

If there is no release harness, packaging still succeeds. The app searches for a
bundled executable, builds in the selected project, common Grok installation
locations, and the inherited `PATH`. Choose an executable in **Settings → Grok
harness** if one is not found. `GROK_BUILD_ROOT` can also identify a repository
containing a debug or release harness when launching from a shell.

For development without packaging:

```sh
swift run --package-path desktop/macOS GrokDesktop
swift test --package-path desktop/macOS
```

## Use the app

1. Choose **Open Project** and select the folder Grok should work in.
2. In **Settings**, check the harness path. Existing CLI credentials are reused;
   the xAI, OpenRouter, and OpenAI Codex buttons launch the harness's browser
   sign-in flow when needed.
3. Start a task and send a prompt. Responses stream into the conversation, with
   expandable thinking and tool output, plan progress, permission requests,
   project trust decisions, and agent questions.
4. Open **Changes** to inspect staged, unstaged, and untracked files. Select a
   file to read its diff; use the refresh button after external edits.

The sidebar groups tasks by project and supports task search, pinning, and
archiving. **Task → Import Harness Tasks** imports saved sessions for the selected
project; selecting an imported task loads its transcript and lets you continue
it. Available model and mode choices appear in the composer after connecting to
the harness; the model picker searches both names and provider IDs. Settings
includes system, light, and dark appearance. Unsent drafts are retained while
switching between tasks and projects during the app session.

The app uses the CLI's account and configuration files, including provider
credentials under `~/.grok` (or the harness's configured home). It does not copy
API keys into desktop preferences. Apps launched from Finder do not necessarily
inherit environment variables from your shell; saved CLI credentials work across
both launch methods. See the [authentication guide](../../crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md).

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New task | ⌘N |
| Open project | ⇧⌘O |
| Search tasks | ⌘K |
| Toggle sidebar | ⌘B |
| Toggle changes inspector | ⌘J |
| Settings | ⌘, |
| Send message | Return |
| Insert a new line | Shift-Return |
| Stop the current task | ⌘. |

## Local data and current scope

Projects, conversation transcripts, session IDs, pins, and archive state are
saved locally in `~/Library/Application Support/Grok Desktop/state.json`, with
owner-only file permissions. The harness path and appearance are stored in macOS
preferences. The harness separately retains its own session history and sends
prompts to the configured model provider as usual.

Quitting stops active desktop connections and saves conversations. Reopening a
task resumes its saved harness session when you send another prompt; work does
not continue in the desktop app after it quits.

The changes inspector is read-only; it does not stage, commit, or revert files.
Large diff previews are capped at 1 MiB per section. **Open in Terminal** launches
macOS Terminal at the project folder; there is no embedded interactive terminal.
Attachments and a desktop slash-command interface are not implemented.

## Validation

`swift test --package-path desktop/macOS` runs process-backed ACP tests, task
lifecycle and transcript tests, question-response tests, and temporary Git
repository fixtures. These tests use isolated state and an offline harness;
they require no provider account and do not modify your real projects.

For manual UI testing without inference, choose the executable
`Tests/Fixtures/mock-grok.py` in Settings. It clearly labels its output as an
offline fixture. Prompts containing `fixture:permission`, `fixture:question`,
`fixture:plan`, `fixture:trust`, or `fixture:wait` exercise the interactive flows.
Restore the real harness executable afterward. Regenerate the app icon with
`swift desktop/macOS/scripts/make-icon.swift desktop/macOS/Resources/AppIcon.icns`
from the repository root.

## Distribution

The generated app is **ad hoc signed for local use**, not Developer ID signed or
notarized, and has no automatic updater. Rebuild to update it. `SIGN_IDENTITY`
overrides the packaging signing identity, but the script does not perform
notarization or provide a complete distribution pipeline. The app build targets
the architecture of the build machine.
