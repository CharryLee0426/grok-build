/* Self-contained trace viewer. Recorded values are text, never executable HTML. */
"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const sourceJson = $("trace-data").textContent;
  const data = JSON.parse(sourceJson);
  const events = data.events.filter(event => event.kind !== "artifact");
  const PAGE_SIZE = 80;
  const TURN_PAGE_SIZE = 30;
  const narrowLayout = window.matchMedia("(max-width: 720px)");
  const state = { matches: events, selected: null, page: 0, turnPage: 0, tab: "content", sessionReady: false };
  const byIndex = new Map(events.map(event => [event.index, event]));
  const toolsByEvent = new Map();
  const toolsById = new Map();
  for (const tool of data.tools) {
    const sameId = toolsById.get(tool.id) || [];
    sameId.push(tool);
    toolsById.set(tool.id, sameId);
    for (const index of tool.event_indices) {
      const linked = toolsByEvent.get(index) || [];
      linked.push(tool);
      toolsByEvent.set(index, linked);
    }
  }
  const number = value => value == null ? "—" : Number(value).toLocaleString();
  const countLabel = (value, label) => `${number(value)} ${label}${value === 1 ? "" : "s"}`;
  const present = value => value != null && value !== "";
  const human = value => String(value || "unknown").replace(/[_-]/g, " ");
  const json = value => JSON.stringify(value, null, 2);
  const isError = event => /error|fail/i.test(event.kind) || /error|fail/i.test(event.status || "");
  const errors = events.filter(isError);
  const usageArtifact = data.artifacts.filter(artifact => /(^|\/)usage\.json$/.test(artifact.name))
    .sort((a, b) => a.name.split("/").length - b.name.split("/").length || a.name.length - b.name.length)[0];
  const usage = usageArtifact && typeof usageArtifact.content === "object" ? usageArtifact.content : null;
  const turnUsage = new Map((usage && Array.isArray(usage.turns) ? usage.turns : []).map(turn => [turn.turnNumber, turn]));
  const cost = row => {
    if (!row || !(row.costUsdTicks > 0)) return "—";
    const amount = row.costUsdTicks / 1e10;
    return `${row.costIsPartial ? "≥ " : ""}$${amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: amount < 0.01 ? 6 : 4 })}`;
  };
  const duration = value => {
    if (value == null) return "—";
    if (value < 1000) return `${number(value)} ms`;
    if (value < 60000) return `${(value / 1000).toFixed(value < 10000 ? 2 : 1)} s`;
    if (value < 3600000) return `${Math.floor(value / 60000)}m ${Math.floor(value % 60000 / 1000)}s`;
    return `${Math.floor(value / 3600000)}h ${Math.floor(value % 3600000 / 60000)}m`;
  };
  const date = value => {
    if (!present(value)) return "—";
    const parsed = new Date(value);
    return Number.isNaN(parsed.valueOf()) ? value : parsed.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "medium" });
  };
  const time = value => {
    const parsed = new Date(value);
    return Number.isNaN(parsed.valueOf()) ? String(value) : parsed.toLocaleTimeString(undefined, { hour12: false });
  };
  const category = event => {
    if (isError(event)) return "error";
    if (/reason|thinking|analysis/.test(event.kind)) return "reasoning";
    if (/tool.*(result|complet|update)|^tool$/.test(event.kind)) return "result";
    if (/tool|permission|command/.test(event.kind)) return "tool";
    if (/user/.test(event.kind)) return "user";
    if (/assistant|message/.test(event.kind)) return "assistant";
    return "system";
  };
  function node(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text != null) element.textContent = String(text);
    return element;
  }
  function button(label, className, action) {
    const element = node("button", className, label);
    element.type = "button";
    element.addEventListener("click", action);
    return element;
  }
  function metadata(target, entries) {
    for (const [label, value, mono] of entries) {
      target.append(node("dt", "", label), node("dd", mono ? "mono" : "", present(value) ? value : "—"));
    }
  }
  function code(value) {
    const element = node("pre", "json-block");
    element.append(node("code", "", typeof value === "string" ? value : json(value)));
    return element;
  }
  let toastTimer;
  function announce(message) {
    $("announcement").textContent = message;
    $("announcement").hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { $("announcement").hidden = true; }, 3500);
  }
  function download(value, filename, alreadySerialized = false) {
    const url = URL.createObjectURL(new Blob([alreadySerialized ? value : json(value)], { type: "application/json;charset=utf-8" }));
    const link = node("a");
    link.href = url;
    link.download = filename;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  async function copyJson() {
    const event = byIndex.get(state.selected);
    if (!event) return;
    const text = json(event.raw);
    try {
      if (!navigator.clipboard || !navigator.clipboard.writeText) throw new Error("Clipboard API unavailable");
      await navigator.clipboard.writeText(text);
      announce("Event JSON copied.");
    } catch (_) {
      const previousFocus = document.activeElement;
      const field = node("textarea");
      field.value = text;
      field.setAttribute("aria-label", "Event JSON to copy");
      field.style.position = "fixed";
      field.style.left = "-9999px";
      document.body.append(field);
      field.select();
      let copied = false;
      try { copied = document.execCommand("copy"); } catch (_) { /* Local pages may deny clipboard access. */ }
      field.remove();
      if (previousFocus) previousFocus.focus();
      announce(copied ? "Event JSON copied." : "Clipboard unavailable. Download the event from the Raw tab.");
    }
  }
  function renderHeader() {
    document.title = `${data.title || "Agent trace"} · Grok Build`;
    $("session-title").textContent = data.title || "Agent trace";
    $("session-subtitle").textContent = [data.model, data.session_id].filter(present).join(" · ");
    const stats = [countLabel(events.length, "event"), countLabel(data.turns.length, "turn"), countLabel(data.tools.length, "tool")];
    if (data.summary.duration_ms != null) stats.push(duration(data.summary.duration_ms));
    if (data.summary.total_tokens != null) stats.push(`${number(data.summary.total_tokens)} tokens`);
    if (errors.length) stats.push(countLabel(errors.length, "error"));
    $("session-stats").textContent = stats.join(" · ");
    $("next-error").disabled = !errors.length;
    $("next-error").title = errors.length ? `${number(errors.length)} recorded errors · E` : "No recorded errors";
  }
  function renderTiming() {
    const timed = events.map(event => ({ event, start: event.timestamp ? Date.parse(event.timestamp) : NaN }))
      .filter(item => Number.isFinite(item.start));
    const untimed = events.length - timed.length;
    if (!timed.length) {
      $("timing-overview").hidden = !events.length;
      $("timing-note").textContent = events.length ? "No event timestamps recorded" : "";
      $("timing-start").textContent = "—";
      $("timing-end").textContent = "—";
      return;
    }
    const start = timed.reduce((minimum, item) => Math.min(minimum, item.start), Infinity);
    // A completion record's duration ends at its timestamp. Plot timestamps only
    // rather than presenting every recorded duration as a forward-running span.
    const end = timed.reduce((maximum, item) => Math.max(maximum, item.start), -Infinity);
    const span = Math.max(1, end - start);
    // A bounded overview keeps large recordings usable; the ledger retains all events.
    const stride = Math.max(1, Math.ceil(timed.length / 600));
    const shown = timed.filter((_, index) => index % stride === 0 || index === timed.length - 1);
    const fragment = document.createDocumentFragment();
    for (const { event, start: eventStart } of shown) {
      const mark = button("", `timing-mark ${category(event)}`, () => selectEvent(event.index, true));
      mark.style.left = `clamp(0px, ${(eventStart - start) / span * 100}%, calc(100% - 3px))`;
      mark.title = `${event.title || human(event.kind)} · ${date(event.timestamp)}${event.duration_ms != null ? ` · ${duration(event.duration_ms)}` : ""}`;
      mark.setAttribute("aria-label", `Event ${event.index + 1}: ${mark.title}`);
      // The ledger is the keyboard-accessible equivalent of this compact overview.
      mark.tabIndex = -1;
      fragment.append(mark);
    }
    $("timing-track").append(fragment);
    $("timing-start").textContent = time(start);
    $("timing-end").textContent = time(end);
    $("timing-start").title = date(start);
    $("timing-end").title = date(end);
    const notes = [];
    if (stride > 1) notes.push(`${number(shown.length)} of ${number(timed.length)} timed events shown`);
    if (untimed) notes.push(`${number(untimed)} untimed ${untimed === 1 ? "record" : "records"}`);
    $("timing-note").textContent = notes.join(" · ");
  }
  function initializeFilters() {
    for (const kind of [...new Set(events.map(event => event.kind))].sort()) {
      const option = node("option", "", human(kind));
      option.value = kind;
      $("kind").append(option);
    }
    for (const turn of [...new Set(events.filter(event => event.turn != null).map(event => event.turn))].sort((a, b) => a - b)) {
      const option = node("option", "", `Turn ${turn}`);
      option.value = String(turn);
      $("turn").append(option);
    }
    if (events.some(event => event.turn == null)) {
      const option = node("option", "", "Unassigned");
      option.value = "none";
      $("turn").append(option);
    }
    const sources = new Map();
    for (const event of events) sources.set(event.source, (sources.get(event.source) || 0) + 1);
    for (const [source, count] of [...sources].sort(([a], [b]) => a.localeCompare(b))) {
      const option = node("option", "", `${source} (${number(count)})`);
      option.value = source;
      $("source-filter").append(option);
    }
  }
  const searchCache = new Map();
  let searchCacheBytes = 0;
  function searchable(event) {
    if (searchCache.has(event.index)) return searchCache.get(event.index);
    const text = JSON.stringify(event.raw).toLocaleLowerCase();
    const bytes = text.length * 2;
    if (searchCacheBytes + bytes <= 8 * 1024 * 1024) {
      searchCache.set(event.index, text);
      searchCacheBytes += bytes;
    }
    return text;
  }
  function applyFilters() {
    const query = $("search").value.trim().toLocaleLowerCase();
    const kind = $("kind").value;
    const turn = $("turn").value;
    const source = $("source-filter").value;
    state.matches = events.filter(event => {
      if (kind && event.kind !== kind) return false;
      if (source && event.source !== source) return false;
      if (turn === "none" ? event.turn != null : turn && String(event.turn) !== turn) return false;
      if (!query) return true;
      const summary = `${event.title}\n${event.text}\n${event.kind}\n${event.source}\n${event.tool_call_id || ""}\n${event.status || ""}\n${event.timestamp || ""}`.toLocaleLowerCase();
      return summary.includes(query) || searchable(event).includes(query);
    });
    state.page = 0;
    if (!state.matches.some(event => event.index === state.selected)) closeInspector(false);
    $("reset-filters").hidden = !(query || kind || turn || source);
    $("filters-toggle").classList.toggle("active", Boolean(turn || source));
    renderEvents();
    $("event-list").scrollTop = 0;
  }
  function clearFilters() {
    for (const name of ["search", "kind", "turn", "source-filter"]) $(name).value = "";
    applyFilters();
  }
  function pagination(target, page, total, size, action) {
    target.replaceChildren();
    target.append(node("span", "pagination-info", total ? `${number(page * size + 1)}–${number(Math.min((page + 1) * size, total))} of ${number(total)}` : "0 events"));
    if (total <= size) return;
    const actions = node("div", "pagination-actions");
    const previous = button("Previous", "", () => action(page - 1));
    previous.disabled = page === 0;
    const next = button("Next", "", () => action(page + 1));
    next.disabled = (page + 1) * size >= total;
    actions.append(previous, next);
    target.append(actions);
  }
  function boundary(event) {
    if (!event.timestamp) return `Recorded transcript · ${event.source}${event.turn == null ? "" : ` · Turn ${event.turn}`}`;
    return event.turn == null ? "Session events" : `Turn ${event.turn}`;
  }
  function eventPayload(event) {
    const raw = event.raw;
    return raw && (raw.params && raw.params.update || raw.update || raw);
  }
  function eventPreview(event) {
    if (event.text) return event.text.slice(0, 1200).replace(/\s+/g, " ").slice(0, 500);
    const raw = eventPayload(event);
    if (!raw || typeof raw !== "object") return "";
    return [raw.phase, raw.status, raw.model_id, raw.model, raw.reason, raw.error_message]
      .filter(value => typeof value === "string" || typeof value === "number").join(" · ").slice(0, 500);
  }
  function kindLabel(event) {
    const type = category(event);
    if (type === "system") return /phase/.test(event.kind) ? "phase" : /turn/.test(event.kind) ? "turn" : human(event.kind);
    if (type === "result") return "tool result";
    return type;
  }
  function renderEvents() {
    const target = $("event-list");
    const oldScroll = target.scrollTop;
    target.replaceChildren();
    $("result-count").textContent = state.matches.length === events.length ? `${number(events.length)} events` : `${number(state.matches.length)} of ${number(events.length)} events`;
    if (!state.matches.length) {
      const empty = node("div", "empty-state");
      empty.append(node("p", "", events.length ? "No matching events" : "No events recorded"));
      if (events.length) empty.append(button("Clear filters", "", clearFilters));
      else if (data.artifacts.length) empty.append(button("View session files", "", showSession));
      target.append(empty);
    }
    const fragment = document.createDocumentFragment();
    let previousBoundary = null;
    for (const event of state.matches.slice(state.page * PAGE_SIZE, (state.page + 1) * PAGE_SIZE)) {
      const group = boundary(event);
      if (group !== previousBoundary) {
        const separator = node("div", "turn-row", group);
        separator.setAttribute("role", "presentation");
        fragment.append(separator);
        previousBoundary = group;
      }
      const item = node("div", "ledger-item");
      item.setAttribute("role", "listitem");
      const row = button("", "ledger-row", () => selectEvent(event.index));
      row.dataset.index = String(event.index);
      row.setAttribute("aria-current", String(event.index === state.selected));
      row.setAttribute("aria-label", `Event ${event.index + 1}, ${human(event.kind)}: ${event.title}${isError(event) ? ", error" : ""}`);
      const summary = node("span", "event-summary");
      summary.append(node("span", "event-title", event.title || human(event.kind)));
      const preview = eventPreview(event);
      if (preview) summary.append(node("span", "event-preview", preview));
      const timing = node("span", "event-time");
      const elapsed = node("span", "", event.elapsed_ms != null ? `+${duration(event.elapsed_ms)}` : event.timestamp ? time(event.timestamp) : "—");
      elapsed.title = event.elapsed_ms != null ? "Time since first recorded timestamp" : event.timestamp ? date(event.timestamp) : "Timestamp not recorded";
      timing.append(elapsed);
      if (event.duration_ms != null) {
        const recordedDuration = node("span", "event-duration", duration(event.duration_ms));
        recordedDuration.title = "Recorded duration";
        timing.append(recordedDuration);
      }
      timing.title = event.timestamp ? date(event.timestamp) : "Timestamp not recorded";
      row.append(node("span", `event-kind ${category(event)}`, kindLabel(event)), summary, timing);
      item.append(row);
      fragment.append(item);
    }
    target.append(fragment);
    target.scrollTop = oldScroll;
    pagination($("pagination"), state.page, state.matches.length, PAGE_SIZE, page => {
      state.page = page;
      renderEvents();
      target.scrollTop = 0;
    });
  }
  function associatedTools(event) {
    const direct = toolsByEvent.get(event.index);
    if (direct && direct.length) return direct;
    return (toolsById.get(event.tool_call_id) || []).filter(tool => tool.turn == null || event.turn == null || tool.turn === event.turn);
  }
  function selectEvent(index, reveal = false, focus = false) {
    if (!byIndex.has(index)) return;
    let position = state.matches.findIndex(event => event.index === index);
    if (position < 0) {
      clearFilters();
      position = state.matches.findIndex(event => event.index === index);
    }
    const event = byIndex.get(index);
    if (state.selected !== index) state.tab = associatedTools(event).length ? category(event) === "result" || isError(event) ? "output" : "input" : "content";
    state.selected = index;
    const page = Math.floor(position / PAGE_SIZE);
    if (page !== state.page) {
      state.page = page;
      renderEvents();
    } else {
      for (const row of $("event-list").querySelectorAll("button[data-index]")) row.setAttribute("aria-current", String(Number(row.dataset.index) === index));
    }
    $("inspector").hidden = false;
    $("workbench").classList.add("inspecting");
    renderInspector();
    const row = $("event-list").querySelector(`button[data-index="${Number(index)}"]`);
    if (row && (reveal || focus)) {
      if (focus) row.focus({ preventScroll: true });
      const list = $("event-list");
      const top = row.getBoundingClientRect().top - list.getBoundingClientRect().top + list.scrollTop;
      if (top < list.scrollTop) list.scrollTop = top;
      else if (top + row.offsetHeight > list.scrollTop + list.clientHeight) list.scrollTop = top + row.offsetHeight - list.clientHeight;
    }
    syncInspectorLayout();
    if (narrowLayout.matches) $("close-inspector").focus({ preventScroll: true });
  }
  function syncInspectorLayout() {
    const ledger = $("event-list").closest(".ledger");
    ledger.inert = narrowLayout.matches && state.selected != null;
    if (ledger.inert && ledger.contains(document.activeElement)) $("close-inspector").focus({ preventScroll: true });
  }
  function closeInspector(restoreFocus = true) {
    const selected = state.selected;
    state.selected = null;
    $("inspector").hidden = true;
    $("workbench").classList.remove("inspecting");
    syncInspectorLayout();
    for (const row of $("event-list").querySelectorAll("button[data-index]")) row.setAttribute("aria-current", "false");
    if (restoreFocus) {
      const row = $("event-list").querySelector(`button[data-index="${Number(selected)}"]`);
      if (row) row.focus({ preventScroll: true });
    }
  }
  function sourceDetails(event) {
    const details = node("details", "source-details");
    details.append(node("summary", "", "Source & metadata"));
    const list = node("dl", "metadata");
    metadata(list, [
      ["Event", event.index + 1], ["Source", event.source, true], ["Line", event.line],
      ["Kind", event.kind], ["Timestamp", event.timestamp], ["Elapsed (ms)", event.elapsed_ms],
      ["Duration (ms)", event.duration_ms], ["Turn", event.turn], ["Call ID", event.tool_call_id, true], ["Status", event.status]
    ]);
    details.append(list);
    return details;
  }
  function structuredContent(panel, raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      panel.append(code(raw));
      return;
    }
    const fields = node("dl", "metadata event-fields");
    const nested = [];
    for (const [key, value] of Object.entries(raw)) {
      if (value != null && typeof value === "object") nested.push([key, value]);
      else fields.append(node("dt", "", key), node("dd", "", value === null ? "null" : String(value)));
    }
    if (fields.childElementCount) panel.append(fields);
    for (const [key, value] of nested) panel.append(node("div", "content-label", key), code(value));
    if (!fields.childElementCount && !nested.length) panel.append(code(raw));
  }
  function renderInspector(focusTab = false) {
    const event = byIndex.get(state.selected);
    if (!event) return;
    const linked = associatedTools(event);
    const tabs = linked.length ? [["input", "Input"], ["output", "Output"], ["raw", "Raw"]] : [["content", "Content"], ["raw", "Raw"]];
    if (!tabs.some(([name]) => name === state.tab)) state.tab = tabs[0][0];
    $("detail-title").textContent = event.title || human(event.kind);
    $("detail-meta").textContent = [`#${event.index + 1}`, event.turn == null ? null : `Turn ${event.turn}`, event.status, event.duration_ms == null ? null : duration(event.duration_ms)].filter(present).join(" · ");
    $("detail-tabs").replaceChildren();
    for (const [name, label] of tabs) {
      const tab = button(label, "detail-tab", () => { state.tab = name; renderInspector(true); });
      tab.id = `tab-${name}`;
      tab.dataset.tab = name;
      tab.setAttribute("role", "tab");
      tab.setAttribute("aria-selected", String(name === state.tab));
      tab.setAttribute("aria-controls", "detail-content");
      tab.tabIndex = name === state.tab ? 0 : -1;
      tab.addEventListener("keydown", key => {
        let position = tabs.findIndex(([item]) => item === name);
        if (key.key === "ArrowRight") position = (position + 1) % tabs.length;
        else if (key.key === "ArrowLeft") position = (position + tabs.length - 1) % tabs.length;
        else if (key.key === "Home") position = 0;
        else if (key.key === "End") position = tabs.length - 1;
        else return;
        key.preventDefault();
        state.tab = tabs[position][0];
        renderInspector(true);
      });
      $("detail-tabs").append(tab);
      if (focusTab && name === state.tab) tab.focus();
    }
    const panel = $("detail-content");
    panel.replaceChildren();
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("aria-labelledby", `tab-${state.tab}`);
    panel.tabIndex = 0;
    if (state.tab === "raw") {
      panel.append(button("Download event JSON", "text-button", () => download(event.raw, `grok-trace-event-${event.index + 1}.json`)), code(event.raw));
    } else if (linked.length) {
      for (const tool of linked) {
        const section = node("section", "tool-section");
        const meta = node("dl", "metadata tool-meta");
        metadata(meta, [["Tool", tool.name], ["Call ID", tool.id, true], ["Status", tool.status], ["Duration", duration(tool.duration_ms)]]);
        section.append(meta);
        const value = tool[state.tab];
        if (value != null) section.append(code(value));
        else section.append(node("p", "missing-data", `${state.tab === "input" ? "Input" : "Output"} not recorded.`));
        const related = node("div", "related-events");
        for (const index of tool.event_indices) {
          const other = byIndex.get(index);
          if (other && index !== event.index) related.append(button(`#${index + 1} ${human(other.kind)}`, "text-button", () => selectEvent(index, true)));
        }
        if (related.childElementCount) section.append(node("div", "content-label", "Related events"), related);
        panel.append(section);
      }
    } else if (category(event) === "system") {
      structuredContent(panel, eventPayload(event));
    } else if (event.text) {
      panel.append(node("div", "event-text", event.text));
    } else {
      structuredContent(panel, eventPayload(event));
    }
    panel.append(sourceDetails(event));
    panel.scrollTop = 0;
  }
  function renderTurns() {
    const target = $("turn-list");
    target.replaceChildren();
    if (!data.turns.length) {
      target.append(node("p", "missing-data", "No turn boundaries recorded."));
      return;
    }
    for (const turn of data.turns.slice(state.turnPage * TURN_PAGE_SIZE, (state.turnPage + 1) * TURN_PAGE_SIZE)) {
      const row = node("div", "session-turn");
      const select = button(`Turn ${turn.number}`, "text-button", () => {
        $("session-dialog").close();
        $("turn").value = String(turn.number);
        $("filters-panel").hidden = false;
        $("filters-toggle").setAttribute("aria-expanded", "true");
        applyFilters();
      });
      const usageRow = turnUsage.get(turn.number);
      row.append(select, node("span", "", [turn.model, turn.status, `${number(turn.event_count)} events`, duration(turn.duration_ms), usageRow ? `${number(usageRow.totalTokens)} tokens · ${number(usageRow.modelCalls)} calls · ${cost(usageRow)}` : null].filter(present).join(" · ")));
      row.title = `Started: ${turn.started_at || "not recorded"}\nEnded: ${turn.ended_at || "not recorded"}`;
      target.append(row);
    }
    const controls = node("div", "session-pagination");
    pagination(controls, state.turnPage, data.turns.length, TURN_PAGE_SIZE, page => { state.turnPage = page; renderTurns(); });
    target.append(controls);
  }
  function renderModelUsage(models) {
    if (!models || !Object.keys(models).length) return;
    const table = node("table", "usage-table");
    const head = node("thead");
    const labels = node("tr");
    for (const label of ["Model", "Calls", "Input", "Cache read", "Cache write", "Reasoning", "Output", "Total", "Cost"]) {
      const cell = node("th", "", label);
      cell.scope = "col";
      labels.append(cell);
    }
    head.append(labels);
    const body = node("tbody");
    for (const [model, row] of Object.entries(models)) {
      const line = node("tr");
      const title = node("th", "", `${model}${row.usageIsIncomplete ? " (incomplete)" : ""}`);
      title.scope = "row";
      line.append(title);
      for (const field of ["modelCalls", "inputTokens", "cachedReadTokens", "cacheCreationTokens", "reasoningTokens", "outputTokens", "totalTokens"]) line.append(node("td", "", number(row[field])));
      line.append(node("td", "", cost(row)));
      body.append(line);
    }
    table.append(head, body);
    $("model-usage").append(table);
  }
  function renderArtifact() {
    const artifact = data.artifacts[Number($("artifact-select").value)];
    $("artifact-content").textContent = artifact ? typeof artifact.content === "string" ? artifact.content : json(artifact.content) : "No session files recorded.";
  }
  function showSession() {
    if (!state.sessionReady) {
      metadata($("recording-meta"), [
        ["Session ID", data.session_id, true], ["Model", data.model], ["Working directory", data.cwd, true],
        ["Source", data.source, true], ["Created", data.created_at], ["Updated", data.updated_at],
        ["Schema", data.schema_version], ["Events", number(events.length)], ["Session files", number(data.artifacts.length)]
      ]);
      metadata($("usage-meta"), [
        ["Input tokens", number(data.summary.input_tokens)], ["Cache read", number(data.summary.cached_input_tokens)],
        ["Output tokens", number(data.summary.output_tokens)], ["Total tokens", number(data.summary.total_tokens)]
      ]);
      if (usage && usage.session) {
        const session = usage.session;
        metadata($("usage-meta"), [["Cache write", number(session.cacheCreationTokens)], ["Reasoning tokens", number(session.reasoningTokens)], ["Model calls", number(session.modelCalls)], ["Reported cost", cost(session)]]);
        if (session.usageIsIncomplete || session.costIsPartial) {
          $("usage-meta").after(node("p", "subtle-note", [session.usageIsIncomplete ? "Token usage is incomplete." : "", session.costIsPartial ? "Cost is a recorded subtotal." : ""].filter(Boolean).join(" ")));
        }
        renderModelUsage(session.modelUsage);
      }
      renderTurns();
      for (const warning of data.warnings) $("warning-list").append(node("li", "", warning));
      if (!data.warnings.length) $("warning-list").append(node("li", "", "No recording warnings."));
      data.artifacts.forEach((artifact, index) => {
        const option = node("option", "", artifact.name);
        option.value = String(index);
        $("artifact-select").append(option);
      });
      $("artifact-select").disabled = !data.artifacts.length;
      renderArtifact();
      state.sessionReady = true;
    }
    $("session-dialog").showModal();
  }
  function nextError() {
    if (!errors.length) return;
    const current = events.findIndex(event => event.index === state.selected);
    const next = events.slice(current + 1).find(isError) || errors[0];
    selectEvent(next.index, true, true);
    announce(`Error in event ${next.index + 1}: ${next.title}`);
  }
  let searchTimer;
  $("search").addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(applyFilters, 140);
  });
  for (const name of ["kind", "turn", "source-filter"]) $(name).addEventListener("change", applyFilters);
  $("filters-toggle").addEventListener("click", () => {
    const open = $("filters-panel").hidden;
    $("filters-panel").hidden = !open;
    $("filters-toggle").setAttribute("aria-expanded", String(open));
  });
  $("reset-filters").addEventListener("click", clearFilters);
  $("next-error").addEventListener("click", nextError);
  $("copy").addEventListener("click", copyJson);
  $("close-inspector").addEventListener("click", () => closeInspector());
  // Export the exact embedded document: JSON.parse would round integers above 2^53.
  $("export").addEventListener("click", () => download(sourceJson, "grok-agent-trace.json", true));
  $("session-details").addEventListener("click", showSession);
  $("close-session").addEventListener("click", () => $("session-dialog").close());
  $("artifact-select").addEventListener("change", renderArtifact);
  $("shortcuts").addEventListener("click", () => $("shortcut-dialog").showModal());
  $("close-shortcuts").addEventListener("click", () => $("shortcut-dialog").close());
  narrowLayout.addEventListener("change", syncInspectorLayout);
  document.addEventListener("keydown", key => {
    if (key.ctrlKey || key.metaKey || key.altKey) return;
    // Native dialogs own Escape and focus while open.
    if ($("shortcut-dialog").open || $("session-dialog").open) return;
    const active = document.activeElement;
    const editing = /INPUT|TEXTAREA|SELECT/.test(active.tagName) || active.isContentEditable;
    if (key.key === "Escape") {
      key.preventDefault();
      if (state.selected != null) closeInspector();
      else { clearFilters(); if (editing) active.blur(); }
      return;
    }
    if (editing) return;
    const onRow = active.matches("button[data-index]");
    if (key.key === "/") {
      key.preventDefault();
      $("search").focus();
    } else if (key.key === "?") {
      key.preventDefault();
      $("shortcut-dialog").showModal();
    } else if (key.key.toLowerCase() === "e") {
      key.preventDefault();
      nextError();
    } else if (active.closest("button, a, summary, [role=tab]") && !onRow) {
      return;
    } else if (["ArrowDown", "ArrowUp", "j", "k"].includes(key.key)) {
      if (!state.matches.length) return;
      key.preventDefault();
      const direction = ["ArrowDown", "j"].includes(key.key) ? 1 : -1;
      const focused = onRow ? Number(active.dataset.index) : state.selected;
      const current = state.matches.findIndex(event => event.index === focused);
      const next = current < 0 ? 0 : Math.max(0, Math.min(state.matches.length - 1, current + direction));
      selectEvent(state.matches[next].index, true, true);
    }
  });
  renderHeader();
  renderTiming();
  initializeFilters();
  renderEvents();
})();
