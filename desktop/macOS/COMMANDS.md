# Grok Build command inventory and desktop routing

Audited against this checkout on 2026-09-22. This is a source inventory and
integration contract, not a claim that every terminal feature has a native
desktop implementation. The running harness remains authoritative for feature,
tool, account, project-trust, plugin, and skill availability.

## Sources of truth

- [Shell slash catalog and resolver](../../crates/codegen/xai-grok-shell/src/session/slash_commands.rs): built-ins, gates, aliases, skill collision handling, saved workflows, and `commands/list` types.
- [Pager command registration](../../crates/codegen/xai-grok-pager/src/slash/commands/mod.rs): every registered terminal slash action; individual modules supply syntax and aliases.
- [Pager slash guide](../../crates/codegen/xai-grok-pager/docs/user-guide/04-slash-commands.md): user-facing terminal semantics.
- [CLI command tree](../../crates/codegen/xai-grok-pager/src/app/cli.rs): process-level commands, distinct from conversation slash commands.
- [ACP extension dispatch](../../crates/codegen/xai-grok-shell/src/agent/mvp_agent/acp_agent.rs), [extension result envelope](../../crates/codegen/xai-grok-shell/src/session/result.rs), and [session notifications](../../crates/codegen/xai-grok-shell/src/extensions/notification.rs).

## Desktop routing contract

The composer should merge native actions with the live harness command catalog.
Typing `/` opens a searchable list with descriptions, argument hints, and source
badges. Selecting a command with arguments inserts it into the composer; execution
is a separate submit action. Native management commands open their corresponding
panels. Only recognized harness commands and explicitly authored ordinary prompts
go to `session/prompt`; pager-only commands must not silently become model prompts.

Fetch `_x.ai/commands/list` with `{ "cwd": "/project" }` before session creation
and `{ "sessionId": "id" }` afterward. The response is **raw**
`{ "commands": [...], "tools": [...] }`, unlike many wrapped extension responses.
Consume `session/update` with `sessionUpdate: "available_commands_update"` as a
full catalog replacement, including commands removed by a model or skill change.
That update's `_meta.tools` is the current tool set. Each command supplies
`name`, `description`, optional `input.hint`, and optional `_meta` provenance:
`scope`, `path`, `bareName`, `pluginName`, or `workflowSource`.

Rust extension method names omit the leading underscore. Their JSON-RPC wire
names use `_x.ai/...`; standard ACP methods such as `session/set_mode` do not.
Most management methods return JSON-RPC `result` containing another
`{ "result": <payload>, "error": <optional string or object> }` envelope. Check
both error layers. Do not manufacture success on empty or unsupported responses.

Native action names take precedence over conflicting unqualified names; keep
qualified skill entries usable. Shell built-ins reserve their names and the
pager's names, so a skill named `compact` is advertised as e.g. `local:compact`.
Use the advertised name verbatim when invoking a skill or workflow.

## Shell commands available through `session/prompt`

The catalog contains the following potential built-ins. Entries with a gate are
only available when advertised by the current harness. Aliases are accepted by
the resolver but are not separate advertised entries.

| Command and aliases | Arguments / effect | Availability |
| --- | --- | --- |
| `/compact` | Optional instructions about context to preserve | Always |
| `/always-approve`, `/yolo` | `on` or `off`; enables or disables permission bypass | Always |
| `/flush` | Flush conversation memory to disk | Memory enabled |
| `/dream` | Consolidate stored memory | Memory enabled |
| `/memory`, `/mem` | Browse memory; desktop may open a native memory panel | Memory configured |
| `/context` | Context-window and session statistics | Always |
| `/hooks-trust` | Trust current project for hook execution | Hooks |
| `/hooks-list` | List loaded hooks | Hooks |
| `/hooks-add` | Hook file or directory path | Hooks |
| `/hooks-remove` | Previously configured hook path | Hooks |
| `/hooks-untrust` | Remove current project trust | Hooks |
| `/plugins`, `/plugin` | `list`, `reload`, `trust`, `add <path>`, `remove <path>` | Plugins |
| `/plugins install` | `<source> [--trust]` | Plugins |
| `/plugins uninstall` | `<name> [--confirm]` | Plugins |
| `/plugins update` | Optional plugin name; omission updates all | Plugins |
| `/reload-plugins` | Alias action for `/plugins reload` | Plugins |
| `/session-info`, `/status`, `/info` | Model, turns, context, session details | Always |
| `/feedback` | Feedback text | Feedback |
| `/deep-research` | Research query | Workflow launches |
| `/workflow` | `<name> [input]`; or `runs`, `pause <run>`, `resume <run>`, `stop <run>`, `save <run>` | Workflow launch or retained-run management |
| `/goal` | `<objective> [--budget <positive tokens>]`; or `status`, `pause`, `resume`, `clear` | Goal |
| `/loop` | `[interval] <prompt>`; transformed into scheduler instructions | Scheduler |
| `/<advertised-skill>` | Skill arguments; supports qualified scopes/plugins | Enabled, user-invocable skill |
| `/<advertised-workflow>` | Workflow launch arguments | Workflow launches |

The plugin resolver recognizes install/uninstall/update even though its advertised
argument hint only lists the first five operations. A budget flag is parsed only
as a valid positive integer at the end of a goal objective. Bare `/goal` is status.
Named workflows accept `--agent-budget N` and `--effort LEVEL`; the shell validates
launch input. A bare workflow resume cannot increase an exhausted agent budget.

## Pager command inventory and current desktop behavior

This table enumerates every registered pager command, including hidden/debug
entries and the two screen-mode commands. Desktop behavior is checked against
`DesktopCommands.swift`, `AppStore.swift`, `CommandViews.swift`, and
`AdvancedCommands.swift`. **Harness** means forwarding a command only when the
runtime advertises it. **Terminal** means the native feature is not implemented;
use Open in Terminal. Terminal fallbacks are not advertised as native features.
Adapted commands can expose fewer options than the terminal syntax shown here.

The registry contains 74 pager commands.

| Command (source) | Aliases | Syntax | Implemented desktop behavior / limitation |
| --- | --- | --- | --- |
| [`/always-approve`](../../crates/codegen/xai-grok-pager/src/slash/commands/always_approve.rs) | — | `/always-approve` | Harness: explicit on/off; empty arguments enable permission bypass |
| [`/announcements`](../../crates/codegen/xai-grok-pager/src/slash/commands/announcements.rs) | — | `/announcements hide \| show` | Terminal: no announcements preference |
| [`/auto`](../../crates/codegen/xai-grok-pager/src/slash/commands/auto.rs) | — | `/auto` | Terminal: classifier permission toggle not exposed |
| [`/btw`](../../crates/codegen/xai-grok-pager/src/slash/commands/btw.rs) | — | `/btw <question>` | Native side-question panel; uses dedicated RPC and keeps the main turn running |
| [`/cd`](../../crates/codegen/xai-grok-pager/src/slash/commands/cd.rs) | — | `/cd [path]` | Native project picker; optional path selects project |
| [`/compact`](../../crates/codegen/xai-grok-pager/src/slash/commands/compact.rs) | — | `/compact compaction instructions` | Harness: optional context-preservation instructions |
| [`/compact-mode`](../../crates/codegen/xai-grok-pager/src/slash/commands/compact_mode.rs) | — | `/compact-mode` | Native conversation density toggle |
| [`/config-agents`](../../crates/codegen/xai-grok-pager/src/slash/commands/config_agents.rs) | `/agents` | `/config-agents` | Native definitions browser/inspect; no default/switch/editor actions |
| [`/context`](../../crates/codegen/xai-grok-pager/src/slash/commands/context.rs) | — | `/context` | Harness: context and statistics report |
| [`/copy`](../../crates/codegen/xai-grok-pager/src/slash/commands/copy.rs) | — | `/copy [N] [file]` | Native clipboard: latest assistant response; terminal N/file arguments not supported |
| [`/dashboard`](../../crates/codegen/xai-grok-pager/src/slash/commands/dashboard.rs) | `/agents-dashboard`, `/sessions` | `/dashboard` | Adapted: native subagents panel; top-level task navigation is in the sidebar |
| [`/debug`](../../crates/codegen/xai-grok-pager/src/slash/commands/debug.rs) | — | `/debug [scroll\|fps\|log]` | Terminal-only diagnostic overlay |
| [`/delete`](../../crates/codegen/xai-grok-pager/src/slash/commands/delete.rs) | — | `/delete` | Native local-history deletion; harness history retained |
| [`/docs`](../../crates/codegen/xai-grok-pager/src/slash/commands/docs.rs) | `/howto`, `/guides` | `/docs [web\|title]` | Native browser opens Build documentation; guide title selection not supported |
| [`/doctor`](../../crates/codegen/xai-grok-pager/src/slash/commands/doctor.rs) | `/terminal-setup`, `/terminal-check`, `/terminal-info` | `/doctor [fix [FIX]]` | Terminal-only diagnostic/fix flow |
| [`/edit-prompt`](../../crates/codegen/xai-grok-pager/src/slash/commands/edit_prompt.rs) | — | `/edit-prompt` | Native multiline composer substitutes for external-editor flow |
| [`/effort`](../../crates/codegen/xai-grok-pager/src/slash/commands/effort.rs) | — | `/effort <level>` | Native selector or supported level argument |
| [`/quit`](../../crates/codegen/xai-grok-pager/src/slash/commands/exit.rs) | `/exit` | `/quit` | Native application quit |
| [`/expand`](../../crates/codegen/xai-grok-pager/src/slash/commands/expand.rs) | — | `/expand` | Native transcript disclosure controls; terminal command has no direct equivalent |
| [`/export`](../../crates/codegen/xai-grok-pager/src/slash/commands/export.rs) | — | `/export [filename]` | Native Markdown save dialog; filename argument not supported |
| [`/feedback`](../../crates/codegen/xai-grok-pager/src/slash/commands/feedback.rs) | — | `/feedback [text]` | Harness: send supplied text; native feedback form not implemented |
| [`/find`](../../crates/codegen/xai-grok-pager/src/slash/commands/find.rs) | — | `/find [text]` | Native searchable transcript panel; typed query is not prefilled |
| [`/fork`](../../crates/codegen/xai-grok-pager/src/slash/commands/fork.rs) | — | `/fork [--worktree\|--no-worktree] [directive]` | Native same-project session fork; worktree flags/directives not supported |
| [`/gboom`](../../crates/codegen/xai-grok-pager/src/slash/commands/gboom.rs) | — | `/gboom` | Hidden terminal-only game |
| [`/help`](../../crates/codegen/xai-grok-pager/src/slash/commands/help.rs) | — | `/help` | Native searchable command/skill palette |
| [`/history`](../../crates/codegen/xai-grok-pager/src/slash/commands/history.rs) | — | `/history` | Native current-task prompt history with reuse action |
| [`/home`](../../crates/codegen/xai-grok-pager/src/slash/commands/home.rs) | `/welcome` | `/home` | Native new-task screen |
| [`/imagine`](../../crates/codegen/xai-grok-pager/src/slash/commands/imagine.rs) | — | `/imagine <description>` | Adapted: submit explicit image-generation prompt when the matching tool is available |
| [`/imagine-video`](../../crates/codegen/xai-grok-pager/src/slash/commands/imagine_video.rs) | — | `/imagine-video <description>` | Adapted: submit explicit video-generation prompt when the matching tool is available |
| [`/import-claude`](../../crates/codegen/xai-grok-pager/src/slash/commands/import_claude.rs) | — | `/import-claude` | Terminal: native settings import not exposed |
| [`/jump`](../../crates/codegen/xai-grok-pager/src/slash/commands/jump.rs) | — | `/jump` | Adapted: native searchable transcript panel |
| [`/login`](../../crates/codegen/xai-grok-pager/src/slash/commands/login.rs) | — | `/login` | Native Accounts settings |
| [`/logout`](../../crates/codegen/xai-grok-pager/src/slash/commands/logout.rs) | — | `/logout` | Native Accounts settings; choose provider sign-out there |
| [`/loop`](../../crates/codegen/xai-grok-pager/src/slash/commands/loop_cmd.rs) | — | `/loop [interval] <prompt>` | Harness: recurring prompt instructions |
| [`/mcps`](../../crates/codegen/xai-grok-pager/src/slash/commands/mcps.rs) | — | `/mcps` | Native server list/add/toggle/restart/auth and per-tool toggles |
| [`/memory`](../../crates/codegen/xai-grok-pager/src/slash/commands/memory.rs) | `/mem` | `/memory` | Native memory listing, file opening, and enable toggle |
| [`/flush`](../../crates/codegen/xai-grok-pager/src/slash/commands/memory_ops.rs) | — | `/flush` | Harness: flush memory |
| [`/dream`](../../crates/codegen/xai-grok-pager/src/slash/commands/memory_ops.rs) | — | `/dream` | Harness: consolidate memory |
| [`/model`](../../crates/codegen/xai-grok-pager/src/slash/commands/model.rs) | `/m` | `/model <name> [effort]` | Native selector or exact name/ID argument; combined effort argument not supported |
| [`/multiline`](../../crates/codegen/xai-grok-pager/src/slash/commands/multiline.rs) | `/ml` | `/multiline` | Native preference toggle: Return inserts a line and Command-Return sends |
| [`/new`](../../crates/codegen/xai-grok-pager/src/slash/commands/new.rs) | `/clear` | `/new` | Native new task |
| [`/personas`](../../crates/codegen/xai-grok-pager/src/slash/commands/personas.rs) | — | `/personas` | Native bundled/local persona browse/inspect; local files open externally |
| [`/plan`](../../crates/codegen/xai-grok-pager/src/slash/commands/plan.rs) | — | `/plan [description]` | Native ACP plan mode; description sent after acknowledgment |
| [`/hooks`](../../crates/codegen/xai-grok-pager/src/slash/commands/plugin.rs) | — | `/hooks` | Native listing, enable/disable, reload; shell hooks-* operations remain available |
| [`/plugins`](../../crates/codegen/xai-grok-pager/src/slash/commands/plugin.rs) | `/plugin` | `/plugins` | Native list/toggle/reload/install; argument commands forwarded to harness |
| [`/marketplace`](../../crates/codegen/xai-grok-pager/src/slash/commands/plugin.rs) | — | `/marketplace` | Adapted: installed Plugins panel; marketplace source browsing not exposed |
| [`/skills`](../../crates/codegen/xai-grok-pager/src/slash/commands/plugin.rs) | — | `/skills` | Native listing/toggle/add-folder and exact advertised invocation |
| [`/privacy`](../../crates/codegen/xai-grok-pager/src/slash/commands/privacy.rs) | — | `/privacy` | Terminal: harness coding-data settings not exposed |
| [`/queue`](../../crates/codegen/xai-grok-pager/src/slash/commands/queue.rs) | — | `/queue` | Terminal: queued-prompt editor not exposed |
| [`/recap`](../../crates/codegen/xai-grok-pager/src/slash/commands/recap.rs) | `/summarize` | `/recap` | Native session recap through dedicated RPC and asynchronous notification |
| [`/release-notes`](../../crates/codegen/xai-grok-pager/src/slash/commands/release_notes.rs) | `/changelog` | `/release-notes` | Terminal: release-note viewer not exposed |
| [`/remember`](../../crates/codegen/xai-grok-pager/src/slash/commands/remember.rs) | — | `/remember [text]` | Terminal: pager memory-note rewrite/review/save; no save-note ACP endpoint |
| [`/rename`](../../crates/codegen/xai-grok-pager/src/slash/commands/rename.rs) | `/title` | `/rename <title> \| --auto` | Native desktop title edit; --auto behavior not supported |
| [`/resume`](../../crates/codegen/xai-grok-pager/src/slash/commands/resume.rs) | — | `/resume` | Native search and harness history import |
| [`/rewind`](../../crates/codegen/xai-grok-pager/src/slash/commands/rewind.rs) | `/undo` | `/rewind` | Native checkpoint picker, affected-file preview, and confirmed conversation/files/both restore; external conflicts block restore |
| [`/scroll-debug`](../../crates/codegen/xai-grok-pager/src/slash/commands/scroll_debug.rs) | — | `/scroll-debug` | Hidden terminal-only HUD |
| [`/session-info`](../../crates/codegen/xai-grok-pager/src/slash/commands/session_info.rs) | — | `/session-info` | Harness: session details report |
| [`/settings`](../../crates/codegen/xai-grok-pager/src/slash/commands/settings_cmd.rs) | `/config`, `/preferences`, `/prefs` | `/settings` | Native Settings window |
| [`/share`](../../crates/codegen/xai-grok-pager/src/slash/commands/share.rs) | — | `/share` | Terminal: native publish/share action not exposed |
| [`/tasks`](../../crates/codegen/xai-grok-pager/src/slash/commands/tasks.rs) | — | `/tasks` | Native background-task output listing; delegated agents use Subagents panel |
| [`/theme`](../../crates/codegen/xai-grok-pager/src/slash/commands/theme.rs) | `/t` | `/theme <name>` | Native system/light/dark appearance; terminal theme names not supported |
| [`/timeline`](../../crates/codegen/xai-grok-pager/src/slash/commands/timeline.rs) | — | `/timeline` | Adapted: native searchable transcript panel |
| [`/timestamps`](../../crates/codegen/xai-grok-pager/src/slash/commands/timestamps.rs) | — | `/timestamps` | Terminal: timestamp toggle not exposed |
| [`/toggle-mouse-reporting`](../../crates/codegen/xai-grok-pager/src/slash/commands/toggle_mouse_reporting.rs) | — | `/toggle-mouse-reporting` | Terminal-only mouse protocol control |
| [`/transcript`](../../crates/codegen/xai-grok-pager/src/slash/commands/transcript.rs) | `/log` | `/transcript` | Native searchable transcript panel |
| [`/tutorial`](../../crates/codegen/xai-grok-pager/src/slash/commands/tutorial.rs) | `/tour`, `/onboarding` | `/tutorial` | Adapted: browser opens Build documentation |
| [`/usage`](../../crates/codegen/xai-grok-pager/src/slash/commands/usage.rs) | `/cost` | `/usage [show\|manage]` | Native current-process session tokens/cost; billing management not exposed |
| [`/view-plan`](../../crates/codegen/xai-grok-pager/src/slash/commands/view_plan.rs) | `/show-plan`, `/plan-view` | `/view-plan` | Native saved Markdown artifact preview plus ACP steps and pending plan approval |
| [`/vim-mode`](../../crates/codegen/xai-grok-pager/src/slash/commands/vim_mode.rs) | — | `/vim-mode` | Terminal-only scrollback keybindings |
| [`/voice`](../../crates/codegen/xai-grok-pager/src/slash/commands/voice.rs) | — | `/voice` | Terminal: native dictation not exposed |
| [`/workflow`](../../crates/codegen/xai-grok-pager/src/slash/commands/workflow.rs) | — | `/workflow` | Harness: launch/manage operations and textual running-workflow overview |
| [`/workflows`](../../crates/codegen/xai-grok-pager/src/slash/commands/workflows.rs) | — | `/workflows` | Native saved workflow browser with launch action |
| [`/minimal`](../../crates/codegen/xai-grok-pager/src/slash/commands/screen_mode_switch.rs) | — | `/minimal` | Terminal-only screen mode |
| [`/fullscreen`](../../crates/codegen/xai-grok-pager/src/slash/commands/screen_mode_switch.rs) | `/full` | `/fullscreen` | Adapted: macOS window fullscreen; differs from terminal screen-mode switch |

## Management ACP contracts

The tables use actual wire names and JSON key spelling. Optional fields are marked
with `?`; placeholders are types rather than literal JSON values.

### MCP servers and tools

Source: [extensions/mcp.rs](../../crates/codegen/xai-grok-shell/src/extensions/mcp.rs).

| Method | Request | Payload / behavior |
| --- | --- | --- |
| `_x.ai/mcp/list` | `{sessionId?: string, cache?: bool}` | `servers`, `sessionMcpResolved`; refresh with `cache:false` after enrollment |
| `_x.ai/mcp/toggle` | `{session_id, server_name, enabled}` | Toggle a server; harness enforces policy |
| `_x.ai/mcp/toggle_tool` | `{session_id, server_name, tool_name, enabled}` | Toggle an individual tool |
| `_x.ai/mcp/auth_status` | `{session_id}` | Servers with snake_case `server_name` and status |
| `_x.ai/mcp/auth_trigger` | `{session_id, server_name}` | Start auth; may return setup requirements or error |
| `_x.ai/mcp/setup` | `{sessionId, serverName, values: {key: value}}` | Complete a server's declared setup schema |
| `_x.ai/mcp/upsert` | `{session_id, server_name, ...config}` | Add/update user config, then reload; config is flattened harness `McpServerConfig` |
| `_x.ai/mcp/delete` | `{session_id, server_name}` | Remove a locally configured server; managed entries cannot be deleted here |
| `_x.ai/mcp/call` | `{sessionId?, server, serverUrl?, tool, arguments}` | Explicit MCP tool execution |
| `_x.ai/mcp/read_resource` | `{sessionId?, server, uri}` | Resource content |

List entries have `name`, optional `displayName`, `source` (`local`/`managed`),
transport `type` (`stdio`/`http`/`managedGateway`), and optional session state:
`enabled`, `status`, `tools`, `authRequired`, `setupRequired`, `blockedReason`.
The session tool list contains `name`, optional description, and `enabled`.
Treat `_x.ai/mcp/tools_changed`, `_x.ai/mcp/servers_updated`, and initialization
notifications as triggers to refresh the relevant task's catalog. Toggle calls
deliberately use snake_case; setup and list deliberately use camelCase.

### Skills, plugins, hooks, and saved workflows

Sources: [skills](../../crates/codegen/xai-grok-shell/src/extensions/skills.rs),
[skill schema](../../crates/codegen/xai-grok-tools/src/implementations/skills/types.rs),
[plugins](../../crates/codegen/xai-grok-shell/src/extensions/plugins.rs),
[hooks](../../crates/codegen/xai-grok-shell/src/extensions/hooks.rs),
[marketplace](../../crates/codegen/xai-grok-shell/src/extensions/marketplace.rs).

| Method | Request | Payload / behavior |
| --- | --- | --- |
| `_x.ai/skills/list` | `{cwd}` | `skills` |
| `_x.ai/skills/config` | `{cwd?}` | Configured paths, ignore paths, total, skills, message |
| `_x.ai/skills/add` | `{cwd?, path}` | Persist discovery path, reload, return skills |
| `_x.ai/skills/remove` | `{cwd?, path}` | Remove configured path; does not delete source files |
| `_x.ai/skills/reset` | `{cwd?}` | Restore default skills configuration |
| `_x.ai/skills/toggle` | `{cwd?, name, enabled}` | Update disabled-name list and return skills |
| `_x.ai/skills/refresh-baseline` | `{}` | Refresh live session skill baselines after changes |
| `_x.ai/workflows/list` | `{sessionId}` | Saved workflow definitions in this session |
| `_x.ai/plugins/reload` | `{}` | Rebuild registry and fan out to live sessions |

`SkillInfo` fields are **snake_case**, including `display_name`, `plugin_name`,
`argument_hint`, and `user_invocable`; `name`, `description`, `path`, `scope`,
and `enabled` are always useful. Skills can be `local`, `repo`, `user`, `server`,
`bundled`, or `plugin` scoped. The toggle endpoint currently matches bare `name`
across scopes; it is not an independently scoped per-plugin toggle. The slash
catalog, rather than a reconstructed name from the list, is invocation authority.

### Live subagents, background tasks, and agent definitions

Sources: [task handlers](../../crates/codegen/xai-grok-shell/src/extensions/task.rs),
[child messaging](../../crates/codegen/xai-grok-shell/src/extensions/subagent_message.rs),
[bundle catalog](../../crates/codegen/xai-grok-shell/src/extensions/bundle.rs).

| Method | Request | Payload / behavior |
| --- | --- | --- |
| `_x.ai/subagent/list_running` | `{sessionId}` | `subagents` with IDs, description, type, timing and progress |
| `_x.ai/subagent/get` | `{subagentId, block?: false, timeoutMs?}` | `snapshot` including status and finished output/error |
| `_x.ai/subagent/cancel` | `{subagentId}` | Cancellation outcome; may already be finished |
| `_x.ai/subagent/message` | `{sessionId, agentAddress, queue?: false, content:[{type:"text",text}]}` | Feature-gated literal human steering; opaque address from spawn notification |
| `_x.ai/task/list` | `{sessionId}` | Background task snapshots |
| `_x.ai/task/kill` | `{sessionId, taskId, source?: "clientUi"}` | Typed stop outcome |
| `_x.ai/scheduler/delete` | `{sessionId, taskId}` | Delete a scheduled task |
| `_x.ai/bundle/status` | `{}` | `hasCache`, `version`, persona/role/agent/skill names and details |
| `_x.ai/bundle/entry/get` | `{kind: "agent"/"persona"/"role", name}` | Source content for an entry; kind is singular |
| `_x.ai/bundle/sync` | `{force?: true}` | Refresh cache for future construction; does not replace the running agent |

There is no public `subagent/spawn` extension in the audited dispatch. Model tools
and workflow launches create subagents. A desktop **Delegate** action can submit
an explicit delegation prompt and render actual spawn events; it must not claim
that a child exists until the harness reports it. Agent definitions (`/agents`)
are separate from live children and the multi-session dashboard.

`subagent_spawned`, `subagent_progress`, and `subagent_finished` arrive through
`_x.ai/session/update` with `{sessionId, update:{sessionUpdate,...}}`. Their fields
are mostly snake_case, while list/get snapshots are camelCase. Route child session
events using the spawn parent/child mapping. Preserve completed children when
refreshing a list that contains only running children.

### Plan, goal, and other native actions

Sources: [mode dispatch](../../crates/codegen/xai-grok-pager/src/app/dispatch/modes.rs),
[config options](../../crates/codegen/xai-grok-shell/src/agent/handlers/config_option.rs),
[goal updates](../../crates/codegen/xai-grok-shell/src/extensions/notification.rs),
[side questions](../../crates/codegen/xai-grok-shell/src/extensions/btw.rs),
[recap](../../crates/codegen/xai-grok-shell/src/extensions/recap.rs),
[rewind dispatch](../../crates/codegen/xai-grok-shell/src/extensions/rewind.rs),
[rewind actor implementation](../../crates/codegen/xai-grok-shell/src/session/acp_session_impl/rewind.rs).

- Enter plan mode with `session/set_mode {sessionId, modeId:"plan"}`. Await its
  acknowledgment before sending a `/plan <description>` description as a normal
  prompt. Use the advertised non-plan mode to leave. `plan` is not a config-option
  ID. The saved plan preview is the session artifact `plan.md`; ACP plan-progress
  entries alone are not the full plan document. Preserve reverse permission
  requests for `exit_plan_mode` plan approval.
- Change the model or thinking level through advertised `session/set_config_option`
  IDs `model` and `reasoning_effort` (or the existing model setter). Only offer
  supported values; await acknowledgment.
- Goal controls send the exact recognized `/goal ...` prompt. There is no separate
  goal RPC. Render `goal_updated` fields such as `objective`, `status`, `phase`,
  `token_budget`, `tokens_used`, `elapsed_ms`, and `pause_message`. Recognize active,
  complete, cleared, budget-limited, blocked, and multiple paused states. User pause
  and stop behavior belong to the harness; do not infer success from button clicks.
- `_x.ai/btw {sessionId, question}` returns `result.answer` independently of the
  main turn. It can run while the main turn is active; it is not a normal queued
  message. Additional optional `content` supports ACP text and image blocks.
- `_x.ai/recap {sessionId,auto:false}` acknowledges with wrapped `{ok:true}`;
  `{ok:true,disabled:true}` means the feature is disabled. The result arrives via
  `session_recap {summary,auto:false}` or `session_recap_unavailable`. The desktop
  binds these asynchronous results to the requested task and ignores automatic
  recaps when displaying a manually opened panel.
- `_x.ai/rewind/points {sessionId}` returns raw `{rewind_points:[...]}` with
  `prompt_index`, `created_at`, `num_file_snapshots`, `has_file_changes`, and
  `prompt_preview`. `_x.ai/rewind/execute` takes `{sessionId,targetPromptIndex,mode,
  force}`, where `mode` is `conversation_only`, `files_only`, or `all`. Its raw
  response uses `target_prompt_index`, `clean_files`, `conflicts`, `reverted_files`,
  `prompt_text`, `success`, and optional `error`.
  **`force:false` is always a pure preview and returns `success:false` even when
  there are no conflicts. `force:true` performs the restore.** The desktop first
  previews, requires explicit confirmation, then re-previews immediately before
  committing; conflicts or a changed file list require a fresh review. Conversation
  restores reload authoritative history and place the original prompt in the
  composer. The desktop does not offer an external-conflict override.
- `_x.ai/session/state {sessionId,cwd}` returns persisted metadata, including
  `summary.grok_home` and `summary.info.cwd`. The desktop uses those paths to read
  the local saved `plan.md`, including `.cwd` sidecars for long hashed workspace
  directories. It limits preview reads to 1 MiB. This RPC's `plan` column is a
  separate JSON state file, not the Markdown plan.
- `_x.ai/session/usage {sessionId}` returns raw `{usage}`. Token fields are
  camelCase; `costUsdTicks` uses 10 billion ticks per USD. A missing cost or
  `costIsPartial`/`usageIsIncomplete` flag must not be presented as zero cost.
  These in-memory totals reset with a new runtime process. CLI `grok usage` reads
  persisted totals.

## Process-level CLI inventory

These commands configure or launch Grok itself. They are not slash commands and
should not be inserted into `session/prompt`. Native account, project, extensions,
and task controls can cover applicable operations; process maintenance and
terminal transport commands remain available through **Open in Terminal**.

| CLI family | Subcommands / primary operation | Source |
| --- | --- | --- |
| `grok agent` | `stdio`, `headless`, `serve`, `leader`; desktop uses `stdio` | `app/cli.rs` |
| `grok inspect` | Show discovered configuration; `--json` | `app/cli.rs` |
| `grok doctor` | Report; `fix [id]` | `doctor_cmd/mod.rs` |
| `grok leader` | `list`, `info`, `kill` | `app/cli.rs` |
| `grok login`, `logout` | Grok, OpenRouter, OpenAI Codex providers | `app/cli.rs` |
| `grok mcp` | `list`, `add`, `remove`, `enable`, `disable`, `doctor` | `mcp_cmd.rs` |
| `grok plugin` | `list`, `install`, `uninstall` (`rm`/`remove`), `update`, `enable`, `disable`, `details`, `validate`, `tag` | `plugin_cmd.rs` |
| `grok plugin marketplace` | `list`, `add`, `remove`, `update` | `plugin_cmd.rs` |
| `grok memory` | `clear` with workspace/global/all scope | `memory_cmd.rs` |
| `grok models` | List models; optional `--refresh` | `app/cli.rs` |
| `grok sessions` | `list`, `search`, `delete` | `sessions_cmd.rs` |
| `grok usage` | Persisted session/turn token and cost totals | `usage_cmd.rs` |
| `grok setup` | Fetch/install managed configuration; `--json` is read-only | `app/cli.rs` |
| `grok share` | Share session URL; hidden CLI entry | `share_cmd.rs` |
| `grok wrap` | Run another command in PTY with clipboard forwarding | `app/cli.rs` |
| `grok export` | Export a session transcript as Markdown | `export_cmd.rs` |
| `grok trace` | Export/upload trace; `view` opens viewer or exports HTML | `trace_cmd.rs` |
| `grok update` | Check/install version; channel selection | `app/cli.rs` |
| `grok version`, `v` | Version information; `--json` | `app/cli.rs` |
| `grok completions` | Generate shell completions | `app/cli.rs` |
| `grok worktree` | `list` (`ls`), `show`, `rm`, `gc` (`prune`), `db rebuild/stats/path` | `worktree_cmd/mod.rs` |
| `grok du`, `disk-usage` | Grok home disk usage | `disk_usage_cmd.rs` |
| `grok workspace` | `start`, `pause`, `resume`, `stop`, `restart`, `status` (`list`); feature-gated | `app/cli.rs` |
| `grok dashboard` | Launch terminal multi-session dashboard | `app/cli.rs` |

Source paths in this table are relative to
[`crates/codegen/xai-grok-pager/src`](../../crates/codegen/xai-grok-pager/src).
Argument flags are defined alongside each command; the live executable's
`grok <family> --help` is the final authority for a packaged version.
