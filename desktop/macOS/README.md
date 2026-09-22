# Grok Desktop for macOS

A native SwiftUI client for the Grok Build harness in this repository. It brings a
project sidebar, persistent tasks, a focused conversation view, and a changes
inspector to the existing agent runtime. The app launches `grok agent stdio` and
communicates through ACP v1; the harness continues to run tools, manage sandboxing,
and load provider credentials and configuration.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 15 or later, or compatible Command Line Tools with Swift 5.9+ and the
  macOS 14+ SDK. Build with Xcode 26+ to enable native Liquid Glass on macOS 26+.
  Earlier systems use the native material fallback. Run `xcode-select --install`
  if the tools are not installed.
- A Grok CLI with `agent stdio` support, preferably built from this checkout.

The desktop package has no external Swift dependencies and uses Apple's system
frameworks. Building the Rust harness has its own requirements, documented in the
[repository README](../../README.md#building-from-source).

## Build and launch

Run these commands from the repository root:

```sh
# Build the release harness and package the desktop app explicitly.
make build-desktop
open "desktop/macOS/dist/Grok Desktop.app"

# Or build and install it to ~/Applications:
make deploy-desktop
```

The repository default commands (`make`, `make build`, and `make deploy`) only
build or install the CLI/TUI. They do not compile or install the desktop app.
Use `make deploy-desktop DESKTOP_INSTALL_DIR=/Applications` to choose a different
app destination, provided it is writable.

The packaging script embeds the release harness as `Contents/Resources/grok`,
signs that executable, and then signs the app. To reuse an existing harness and
skip its Rust build:

```sh
make build-desktop GROK_BINARY="/absolute/path/to/grok"
```

The lower-level `./desktop/macOS/scripts/build-app.sh` command remains available
for packaging a prebuilt harness; it requires `target/release/xai-grok-pager` or
an explicit `GROK_BINARY`.

Packaging requires a harness and embeds it as the fixed application default.
Settings does not expose an executable path, and old path preferences are ignored.
For unpackaged development, the app discovers builds in the selected project,
common Grok installation locations, and the inherited `PATH`. `GROK_BUILD_ROOT`
can identify a repository containing a debug or release harness.

For development without packaging:

```sh
swift run --package-path desktop/macOS GrokDesktop
swift test --package-path desktop/macOS
```

## Use the app

1. Choose **Open Project** and select the folder Grok should work in.
2. In **Settings**, check **Accounts**. Existing CLI credentials are reused.
   Each provider shows its saved account identity when available, and signed-in
   accounts cannot start another sign-in. OpenRouter API keys do not include an
   account name; this is stated explicitly.
3. Start a task and send a prompt. Responses stream into the conversation, with
   expandable thinking and tool output, plan progress, permission requests,
   project trust decisions, and agent questions.
4. Open **Changes** to inspect staged, unstaged, and untracked files. Select a
   file to read its diff; use the refresh button after external edits.
5. Type **/** in the composer, or press **⇧⌘P**, to browse commands and skills.
   Use the arrow keys to navigate, **Tab** to complete a command, **Return** to
   select it, and **Escape** to dismiss. Commands with arguments fill the composer
   so you can add details before sending. The **+** menu and **Extensions** menu
   provide direct access to the same features.

The command catalog is loaded from the harness for the selected project and
updated during the session. User-invocable skills retain their exact qualified
names, including plugin and scope prefixes. Desktop commands open native views;
shell commands retain the harness's normal slash-command execution semantics.
Unknown commands produce an error instead of becoming ordinary model prompts.

- **MCP servers:** inspect connection status and tools, add remote or local
  servers, enable/disable servers and individual tools, reconnect, authorize, and
  remove locally configured servers. Configuration changes go through the harness.
- **Skills, plugins, hooks, and workflows:** browse discovered extensions, toggle
  supported entries, add a skill folder, install/reload plugins, and prepare skill
  or workflow invocations in the composer.
- **Plan:** `/plan [description]` changes the actual session mode before sending
  the description. `/view-plan` shows the saved Markdown plan, checklist progress,
  and pending approval controls.
- **Goal:** `/goal <objective> [--budget N]` starts a harness goal. The status card
  shows progress and usage; pause, resume, clear, and status controls use the
  harness lifecycle. Pausing a running goal cancels the active turn immediately.
- **Subagents:** inspect live activity, output and failure details, stop children,
  and message addressable agents. Agent definitions and personas have separate
  browsers. Spawning and delegation remain managed by Grok's tools.
- **Other task actions:** `/btw`, `/fork`, `/recap`, `/rewind`, `/tasks`, `/usage`,
  history, transcript search, copy/export, and model/thinking selection have native
  interfaces. Image/video commands appear when their tools are advertised.

[COMMANDS.md](COMMANDS.md) records all 74 pager commands, shell built-ins, CLI
families, exact ACP contracts, and the implemented desktop mapping. Terminal
display/debug commands are not offered as desktop actions. A few pager-only
features, including voice, sharing, privacy configuration, and memory-note
authoring, still require the terminal; typed invocations explain this explicitly.

The native, resizable sidebar groups tasks by project and supports task search,
pinning, archiving, and deletion through the task’s ellipsis or context menu.
Completed tasks show a fixed date instead of a running seconds counter. Deletion
removes the local conversation and prevents history import from adding it back;
the harness’s own history is retained. Active tasks must be stopped first. **Task → Import Harness Tasks** imports saved sessions for the selected
project; selecting an imported task loads its transcript and lets you continue
it. Available model choices load before the first message and when reopening a task;
the model picker searches both names and provider IDs. The composer displays the
model, adjustable thinking level when supported, and conversation mode. Changes
are acknowledged by the harness before sending is re-enabled, and model/thinking
choices persist across relaunches. Settings includes system, light, and dark
appearance. The interface uses system typography, native toolbar controls, and
Liquid Glass on supported systems, respecting reduced transparency and motion. Unsent drafts are retained while
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
| Command palette | ⇧⌘P |
| Enter plan mode | ⌥⌘P |
| Toggle sidebar | ⌘B |
| Toggle changes inspector | ⌘J |
| Settings | ⌘, |
| Send message | Return |
| Insert a new line | Shift-Return |
| Stop the current task | ⌘. |

`/multiline` changes Return to insert a newline and ⌘Return to send. `/compact-mode`
toggles a denser transcript layout.

## Local data and current scope

Projects, conversation transcripts, session IDs, pins, and archive state are
saved locally in `~/Library/Application Support/Grok Desktop/state.json`, with
owner-only file permissions. Appearance is stored in macOS preferences; the harness is selected at build time. The harness separately retains its own session history and sends
prompts to the configured model provider as usual.

Quitting stops active desktop connections and saves conversations. Reopening a
task resumes its saved harness session when you send another prompt; work does
not continue in the desktop app after it quits.

The changes inspector is read-only; it does not stage, commit, or revert files.
Large diff previews are capped at 1 MiB per section. **Open in Terminal** launches
macOS Terminal at the project folder; there is no embedded interactive terminal.
Attachments are not implemented. Agent definitions and personas can be browsed
and opened; authoring and selecting custom agent configurations still use the
harness configuration files or terminal interface. `/fork` currently branches
within the same project, without creating a worktree.

## Validation

`swift test --package-path desktop/macOS` runs process-backed ACP tests, task
lifecycle and transcript tests, question-response tests, and temporary Git
repository fixtures. These tests use isolated state and an offline harness;
they require no provider account and do not modify your real projects.
Command integration tests cover catalog refresh, native routing, exact slash
arguments, qualified skills, MCP management, plan transitions, live goals,
subagent activity, and extension errors. Saved-plan tests use temporary artifacts.

For manual UI testing without inference, build a separate development bundle
with `GROK_BINARY="$PWD/desktop/macOS/Tests/Fixtures/mock-grok.py"` passed to the
packaging script. It clearly labels its output as an offline fixture. Prompts containing `fixture:permission`, `fixture:question`,
`fixture:plan`, `fixture:trust`, or `fixture:wait` exercise the interactive flows.
Rebuild with the real harness afterward.

For isolated development runs, `GROK_DESKTOP_STATE_FILE` selects an absolute path
for desktop state and `GROK_DESKTOP_HARNESS` selects a test executable. The normal
packaged app continues to use its embedded runtime and standard local state.

## Vector app icon

[`Resources/GrokMark.svg`](Resources/GrokMark.svg) is the editable vector source,
reconstructed from the [Grok homepage](https://grok.com/) mark. No downloaded
raster artwork or font glyph is used. The desktop icon places the white mark on
a black macOS rounded-square tile; the in-app symbol uses the same paths.

The packaging script regenerates the icon before building. To regenerate it
independently, run from the repository root:

```sh
swift desktop/macOS/scripts/make-icon.swift desktop/macOS/Resources/AppIcon.icns
```

The generator creates the multi-resolution ICNS, a scalable `Resources/AppIcon.svg`,
a PNG preview in `dist/`, and the native `GrokSymbol.swift` shape. Edit
`GrokMark.svg` to change the geometry, then regenerate; avoid editing the generated
Swift shape directly. Each required icon size is rendered from vector paths.

## Distribution

The generated app is **ad hoc signed for local use**, not Developer ID signed or
notarized, and has no automatic updater. Rebuild to update it. `SIGN_IDENTITY`
overrides the packaging signing identity, but the script does not perform
notarization or provide a complete distribution pipeline. The app build targets
the architecture of the build machine.
