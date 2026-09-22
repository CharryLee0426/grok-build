# Agent trace explorer

Use `grok trace view` to inspect how an agent ran: its prompts and recorded
reasoning, tool calls and results, turn boundaries, failures, usage, and saved
configuration. The terminal and HTML views read the same local snapshot.

```sh
# Open a saved session in the terminal explorer.
grok trace view <session-id>

# Inspect a session directory or an exported trace bundle.
grok trace view ~/.grok/sessions/<encoded-cwd>/<session-id>
grok trace view ./session.tar.gz

# Generate a portable HTML report and open it in a browser.
grok trace view <session-id> --html --open
grok trace view ./session.tar.gz --format html -o trace.html

# Export the normalized data for your own analysis.
grok trace view ./updates.jsonl --format json -o trace.json
grok trace view <session-id> --format json -o -
```

`--format` accepts `tui` (default), `html`, and `json`. `--html` is shorthand
for `--format html`. Without `-o`, HTML and JSON files are saved in
`$GROK_HOME/trace-exports/` (normally `~/.grok/trace-exports/`). `--open` is
available for HTML files. Terminal inspection requires an interactive terminal;
use HTML or JSON in CI and redirected shells.

## Reading a trace

Browse the event list, search for a tool name or text, and filter to a turn or
event category. Select an event to read its content and original JSON. Tool inspection
links calls to their results through the recorded tool-call ID. Error navigation
helps locate failures without stepping through every event.

The artifacts view preserves available context such as the system prompt,
tool definitions, prompt context, session metadata, usage, and subagent metadata.
Inspecting this context helps explain what instructions and tools the model had
available. Subagent metadata describes recorded relationships; separate child
sessions can be opened by their own session ID.

The HTML page opens directly to a compact event ledger with inline turn boundaries
and a timing strip. Select a record to open its inspector; tool records include
linked Input, Output, and Raw tabs. **Session details** contains usage, turn
summaries, recording notes, and all saved files. The timing strip plots recorded
timestamps only; untimed records are identified separately. Large traces are
paged without dropping records from search or export.

The page includes its data and assets, works offline, and adapts to narrow screens.
Its layout follows the ledger and optional inspector pattern in
[DeepSeek Harness's trajectory viewer](https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/client/ui-trajectory).
Press `/` to search, `j` / `k` or the arrow keys to inspect adjacent events, `e` to
find the next error, and `Esc` to close the inspector or clear filters. Keyboard
hints are available in both views.

Terminal controls:

| Key | Action |
| --- | --- |
| `↑` / `↓`, `j` / `k` | Move in the focused pane |
| `Tab` / `Enter` | Switch between timeline and details |
| `1`–`5` | Overview, event, tool I/O, raw JSON, artifacts |
| `/` | Search event text and raw fields |
| `f` | Cycle event categories |
| `t` | Filter to the selected turn |
| `[` / `]` | Previous / next turn |
| `e` | Jump to the next error |
| `J` / `K`, `PgUp` / `PgDn` | Scroll details / page through the focused pane |
| `Esc` | Clear search and filters |
| `?` | Show help |
| `q` / `Ctrl-C` | Exit |

On narrow terminals, `Tab` switches between the two full-width panes.

## What the data can tell you

The viewer presents recorded information. It does not recover unrecorded model
reasoning, infer a hidden execution step, or treat a missing token count as zero.
Different streams can have different timestamp coverage. The report flags
missing timing, malformed records, incomplete data, and uncertain cross-stream
ordering. Stream order is retained where timestamps are unavailable. Duration
measurements come from recorded timestamps or duration fields, rather than the
position of a row in the timeline.

This is a snapshot, not a live tail. Reopen or regenerate the report to include
new events from a running session. The original records remain available for
inspection even when an event type is unfamiliar to the viewer.

The reader accepts up to 32 MiB per text file, 128 MiB of selected content,
256 MiB of decompressed archive data, and 100,000 events. Oversized files are
identified in recording notes; oversized archives or event collections produce
an error. Symlinks are skipped, archives are read without extraction, and binary
attachments remain references in the raw records. Compaction checkpoints appear
as historical artifacts rather than additional live events.

## Exporting and sharing

Viewing a trace does not authenticate, contact the model provider, or upload
session contents. Existing trace exports continue to work:

```sh
grok trace <session-id> --local -o session.tar.gz
grok trace <session-id> --local --json
```

HTML and JSON contain the recorded prompts, source code, tool arguments, output,
and other session data. Review the contents before sharing. New report files are
created with owner-only permissions on Unix. The viewer never executes recorded
tool calls or treats trace text as HTML.
