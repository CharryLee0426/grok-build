//! Read-only, keyboard-first exploration of a recorded agent session.

use std::io::{self, IsTerminal};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use crossterm::{
    cursor::{Hide, Show},
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Frame, Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Clear, List, ListItem, ListState, Paragraph, Tabs},
};
use serde_json::Value;

use super::data::{TraceData, TraceEvent, TraceTool};
use crate::theme::Theme;

/// Opens the trace in the terminal without executing tools or modifying the recording.
pub fn run(data: &TraceData) -> Result<()> {
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!(
            "The trace explorer needs an interactive terminal. Use --format html --output trace.html to export a browser view."
        );
    }
    crate::theme::cache::set(crate::theme::cache::resolve_initial_theme_no_osc11());
    let theme = Theme::current();
    let _guard = TerminalGuard::enter()?;
    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))
        .context("Could not initialize the trace terminal")?;
    let mut state = Explorer::new(data);
    loop {
        terminal.draw(|frame| render(frame, data, &mut state, &theme))?;
        match event::read().context("Could not read terminal input")? {
            Event::Key(key) if key.kind != KeyEventKind::Release => {
                if state.key(data, key) {
                    break;
                }
            }
            Event::Resize(_, _) => {}
            _ => continue,
        }
    }
    Ok(())
}

type PanicHook = dyn Fn(&std::panic::PanicHookInfo<'_>) + Send + Sync + 'static;

/// Restore on both ordinary errors and panics, including this workspace's abort profiles.
struct TerminalGuard {
    previous_hook: Option<Arc<PanicHook>>,
}

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode().context("Could not enable terminal input")?;
        let previous_hook: Arc<PanicHook> = std::panic::take_hook().into();
        let delegate = Arc::clone(&previous_hook);
        std::panic::set_hook(Box::new(move |info| {
            restore_terminal();
            delegate(info);
        }));
        let guard = Self {
            previous_hook: Some(previous_hook),
        };
        execute!(io::stdout(), EnterAlternateScreen, Hide)
            .context("Could not enter the trace terminal")?;
        Ok(guard)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        restore_terminal();
        // Rust forbids changing hooks while unwinding. In that case the hook has
        // already restored the screen and delegates to the original panic reporter.
        if !std::thread::panicking()
            && let Some(previous) = self.previous_hook.take()
        {
            std::panic::set_hook(Box::new(move |info| previous(info)));
        }
    }
}

fn restore_terminal() {
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), Show, LeaveAlternateScreen);
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Filter {
    #[default]
    All,
    Messages,
    Reasoning,
    Tools,
    Errors,
    Lifecycle,
}

impl Filter {
    fn next(self) -> Self {
        match self {
            Self::All => Self::Messages,
            Self::Messages => Self::Reasoning,
            Self::Reasoning => Self::Tools,
            Self::Tools => Self::Errors,
            Self::Errors => Self::Lifecycle,
            Self::Lifecycle => Self::All,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::All => "All events",
            Self::Messages => "Messages",
            Self::Reasoning => "Reasoning",
            Self::Tools => "Tools",
            Self::Errors => "Errors",
            Self::Lifecycle => "Lifecycle",
        }
    }

    fn matches(self, event: &TraceEvent) -> bool {
        let kind = event.kind.to_lowercase();
        match self {
            Self::All => true,
            Self::Messages => {
                ["user", "assistant", "message", "prompt"]
                    .iter()
                    .any(|label| kind.contains(label))
                    && !kind.contains("reason")
                    && !kind.contains("think")
            }
            Self::Reasoning => kind.contains("reason") || kind.contains("think"),
            Self::Tools => kind.contains("tool") || event.tool_call_id.is_some(),
            Self::Errors => is_error(event),
            Self::Lifecycle => [
                "session",
                "turn",
                "usage",
                "status",
                "system",
                "config",
                "permission",
            ]
            .iter()
            .any(|label| kind.contains(label)),
        }
    }
}

const TAB_NAMES: [&str; 5] = ["Overview", "Event", "Tool I/O", "Raw JSON", "Artifacts"];

#[derive(Default)]
struct Explorer {
    visible: Vec<usize>,
    search_index: Vec<String>,
    list: ListState,
    filter: Filter,
    turn: Option<u64>,
    query: String,
    search_before: String,
    searching: bool,
    detail_focus: bool,
    tab: usize,
    scroll: usize,
    viewport_height: usize,
    timeline_page: usize,
    detail_lines: Vec<String>,
    detail_key: Option<(Option<usize>, usize, u16)>,
    help: bool,
}

impl Explorer {
    fn new(data: &TraceData) -> Self {
        let mut state = Self {
            search_index: data
                .events
                .iter()
                .map(|event| {
                    format!(
                        "{} {} {} {} {} {}",
                        event.kind,
                        event.title,
                        event.text,
                        event.source,
                        event.status.as_deref().unwrap_or(""),
                        event.raw
                    )
                    .to_lowercase()
                })
                .collect(),
            tab: 1,
            ..Self::default()
        };
        state.refilter(data);
        state
    }

    fn selected(&self) -> Option<usize> {
        self.list
            .selected()
            .and_then(|index| self.visible.get(index))
            .copied()
    }

    fn visible_event<'a>(&self, data: &'a TraceData, index: usize) -> Option<&'a TraceEvent> {
        self.visible
            .get(index)
            .and_then(|index| data.events.get(*index))
    }

    fn tab_name(&self) -> &'static str {
        TAB_NAMES.get(self.tab).copied().unwrap_or("Event")
    }

    fn refilter(&mut self, data: &TraceData) {
        let previous = self.selected();
        let query = self.query.to_lowercase();
        self.visible = data
            .events
            .iter()
            .enumerate()
            .filter_map(|(index, event)| {
                (self.filter.matches(event)
                    && self.turn.is_none_or(|turn| event.turn == Some(turn))
                    && (query.is_empty()
                        || self
                            .search_index
                            .get(index)
                            .is_some_and(|text| text.contains(&query))))
                .then_some(index)
            })
            .collect();
        let selected = previous
            .and_then(|previous| self.visible.iter().position(|&index| index == previous))
            .or_else(|| (!self.visible.is_empty()).then_some(0));
        self.list.select(selected);
        self.scroll = 0;
        self.detail_key = None;
    }

    fn select(&mut self, index: usize) {
        if self.visible.is_empty() {
            return;
        }
        self.list.select(Some(index.min(self.visible.len() - 1)));
        self.scroll = 0;
    }

    fn move_selection(&mut self, amount: isize) {
        self.select(
            self.list
                .selected()
                .unwrap_or(0)
                .saturating_add_signed(amount),
        );
    }

    fn scroll_detail(&mut self, amount: isize) {
        self.scroll = self
            .scroll
            .saturating_add_signed(amount)
            .min(self.detail_lines.len().saturating_sub(self.viewport_height));
    }

    fn next_error(&mut self, data: &TraceData) {
        if data.events.is_empty() {
            return;
        }
        let start = self.selected().map_or(0, |index| index + 1);
        let next = (start..data.events.len())
            .chain(0..start.min(data.events.len()))
            .find(|&index| data.events.get(index).is_some_and(is_error));
        if let Some(index) = next {
            self.filter = Filter::All;
            self.turn = None;
            self.query.clear();
            self.refilter(data);
            self.select(index);
            self.tab = 1;
        }
    }

    fn next_turn(&mut self, data: &TraceData, forward: bool) {
        let Some(selected) = self.list.selected() else {
            return;
        };
        let turn = self
            .visible_event(data, selected)
            .and_then(|event| event.turn);
        let next = if forward {
            (selected + 1..self.visible.len())
                .find(|&index| self.visible_event(data, index).and_then(|event| event.turn) != turn)
        } else {
            (0..selected)
                .rev()
                .find(|&index| self.visible_event(data, index).and_then(|event| event.turn) != turn)
                .map(|index| {
                    let target = self.visible_event(data, index).and_then(|event| event.turn);
                    (0..=index)
                        .rev()
                        .take_while(|&index| {
                            self.visible_event(data, index).and_then(|event| event.turn) == target
                        })
                        .last()
                        .unwrap_or(index)
                })
        };
        if let Some(index) = next {
            self.select(index);
        }
    }

    /// Returns true only when the explorer should close.
    fn key(&mut self, data: &TraceData, key: KeyEvent) -> bool {
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            return true;
        }
        if self.help {
            self.help = false;
            return false;
        }
        if self.searching {
            match key.code {
                KeyCode::Esc => {
                    self.query.clone_from(&self.search_before);
                    self.searching = false;
                }
                KeyCode::Enter => self.searching = false,
                KeyCode::Backspace => {
                    self.query.pop();
                }
                KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    self.query.clear()
                }
                KeyCode::Char(ch)
                    if !key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
                {
                    self.query.push(ch)
                }
                _ => return false,
            }
            self.refilter(data);
            return false;
        }
        let page = if self.detail_focus {
            self.viewport_height
        } else {
            self.timeline_page
        }
        .max(1) as isize;
        match key.code {
            KeyCode::Char('q') => return true,
            KeyCode::Char('?') => self.help = true,
            KeyCode::Char('/') => {
                self.search_before.clone_from(&self.query);
                self.searching = true;
            }
            KeyCode::Esc => {
                self.query.clear();
                self.filter = Filter::All;
                self.turn = None;
                self.refilter(data);
            }
            KeyCode::Char('f') => {
                self.filter = self.filter.next();
                self.refilter(data);
            }
            KeyCode::Char('t') => {
                self.turn = if self.turn.is_some() {
                    None
                } else {
                    self.selected()
                        .and_then(|index| data.events.get(index))
                        .and_then(|event| event.turn)
                };
                self.refilter(data);
            }
            KeyCode::Char('e') => self.next_error(data),
            KeyCode::Char('[') => self.next_turn(data, false),
            KeyCode::Char(']') => self.next_turn(data, true),
            KeyCode::Tab | KeyCode::BackTab | KeyCode::Enter => {
                self.detail_focus = !self.detail_focus
            }
            KeyCode::Char('1'..='5') => {
                if let KeyCode::Char(number) = key.code {
                    self.tab = number as usize - '1' as usize;
                }
                self.detail_focus = true;
                self.scroll = 0;
            }
            KeyCode::Left | KeyCode::Char('h') => {
                self.tab = (self.tab + TAB_NAMES.len() - 1) % TAB_NAMES.len();
                self.detail_focus = true;
                self.scroll = 0;
            }
            KeyCode::Right | KeyCode::Char('l') => {
                self.tab = (self.tab + 1) % TAB_NAMES.len();
                self.detail_focus = true;
                self.scroll = 0;
            }
            KeyCode::Char('J') => self.scroll_detail(1),
            KeyCode::Char('K') => self.scroll_detail(-1),
            KeyCode::Down | KeyCode::Char('j') => {
                if self.detail_focus {
                    self.scroll_detail(1);
                } else {
                    self.move_selection(1);
                }
            }
            KeyCode::Up | KeyCode::Char('k') => {
                if self.detail_focus {
                    self.scroll_detail(-1);
                } else {
                    self.move_selection(-1);
                }
            }
            KeyCode::PageDown | KeyCode::Char('d') => {
                if self.detail_focus {
                    self.scroll_detail(page);
                } else {
                    self.move_selection(page);
                }
            }
            KeyCode::PageUp | KeyCode::Char('u') => {
                if self.detail_focus {
                    self.scroll_detail(-page);
                } else {
                    self.move_selection(-page);
                }
            }
            KeyCode::Home | KeyCode::Char('g') => {
                if self.detail_focus {
                    self.scroll = 0;
                } else {
                    self.select(0);
                }
            }
            KeyCode::End | KeyCode::Char('G') => {
                if self.detail_focus {
                    self.scroll = self.detail_lines.len().saturating_sub(self.viewport_height);
                } else {
                    self.select(self.visible.len().saturating_sub(1));
                }
            }
            _ => {}
        }
        false
    }
}

fn is_error(event: &TraceEvent) -> bool {
    let status = event.status.as_deref().unwrap_or("").to_lowercase();
    let kind = event.kind.to_lowercase();
    ["error", "fail", "cancel", "reject", "denied"]
        .iter()
        .any(|word| status.contains(word) || kind.contains(word))
}

fn event_color(event: &TraceEvent, theme: &Theme) -> Color {
    if is_error(event) {
        return theme.accent_error;
    }
    if Filter::Tools.matches(event) {
        return theme.accent_tool;
    }
    if Filter::Reasoning.matches(event) {
        return theme.accent_thinking;
    }
    if event.kind.contains("user") {
        return theme.accent_user;
    }
    if event.kind.contains("assistant") {
        return theme.accent_assistant;
    }
    theme.accent_system
}

fn panel(title: String, focused: bool, theme: &Theme) -> Block<'static> {
    Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if focused {
            theme.selection_border
        } else {
            theme.gray_dim
        }))
        .style(Style::default().bg(theme.bg_base).fg(theme.text_primary))
}

fn render(frame: &mut Frame<'_>, data: &TraceData, state: &mut Explorer, theme: &Theme) {
    let area = frame.area();
    frame.render_widget(
        Block::default().style(Style::default().bg(theme.bg_base).fg(theme.text_primary)),
        area,
    );
    if area.width < 24 || area.height < 8 {
        frame.render_widget(
            Paragraph::new("Trace explorer\nResize to at least 24 × 8.\nq exits"),
            area,
        );
        return;
    }
    let [header_area, search_area, content_area, footer_area] = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Length(1),
            Constraint::Min(3),
            Constraint::Length(1),
        ])
        .areas(area);
    render_header(frame, header_area, data, theme);
    render_search(frame, search_area, data, state, theme);
    let compact = area.width < 90;
    if compact {
        if state.detail_focus {
            render_detail(frame, content_area, data, state, theme);
        } else {
            render_timeline(frame, content_area, data, state, theme);
        }
    } else {
        let [timeline_area, detail_area] = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(36), Constraint::Percentage(64)])
            .areas(content_area);
        render_timeline(frame, timeline_area, data, state, theme);
        render_detail(frame, detail_area, data, state, theme);
    }
    let hint = if state.searching {
        " Type to search · Enter apply · Esc cancel · Ctrl-U clear"
    } else if area.width < 70 {
        " q quit  / search  Tab view  ? help"
    } else {
        " ↑↓/jk navigate  Tab focus  1–5 views  / search  f filter  e error  ? help  q quit"
    };
    frame.render_widget(
        Paragraph::new(hint).style(Style::default().fg(theme.text_secondary)),
        footer_area,
    );
    if state.help {
        render_help(frame, area, theme);
    }
}

fn render_header(frame: &mut Frame<'_>, area: Rect, data: &TraceData, theme: &Theme) {
    let summary = &data.summary;
    let first = Line::from(vec![
        Span::styled(
            " grok ",
            Style::default()
                .fg(theme.text_primary)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled("/ trace  ", Style::default().fg(theme.text_secondary)),
        Span::styled(
            clean(&data.title),
            Style::default()
                .fg(theme.text_primary)
                .add_modifier(Modifier::BOLD),
        ),
    ]);
    let mut second = vec![
        Span::styled(
            format!(
                " {} turns   {} events   {} tools   ",
                summary.turn_count, summary.event_count, summary.tool_count
            ),
            Style::default().fg(theme.text_secondary),
        ),
        Span::styled(
            format!("{} errors", summary.error_count),
            Style::default().fg(if summary.error_count > 0 {
                theme.accent_error
            } else {
                theme.text_secondary
            }),
        ),
        Span::styled(
            format!("   {}", duration(summary.duration_ms)),
            Style::default().fg(theme.text_secondary),
        ),
    ];
    if let Some(tokens) = summary.total_tokens {
        second.push(Span::styled(
            format!("   {tokens} tokens"),
            Style::default().fg(theme.accent_model),
        ));
    }
    if !data.warnings.is_empty() {
        second.push(Span::styled(
            format!("   {} warnings", data.warnings.len()),
            Style::default().fg(theme.warning),
        ));
    }
    frame.render_widget(Paragraph::new(vec![first, Line::from(second)]), area);
}

fn render_search(
    frame: &mut Frame<'_>,
    area: Rect,
    data: &TraceData,
    state: &Explorer,
    theme: &Theme,
) {
    let turn = state
        .turn
        .map_or_else(String::new, |turn| format!(" · turn {turn}"));
    let prefix = format!(
        " {}{turn} · {}/{}  ",
        state.filter.name(),
        state.visible.len(),
        data.events.len()
    );
    let search = if state.searching {
        format!("/{}▏", clean(&state.query))
    } else if state.query.is_empty() {
        " / to search event text and raw fields".to_owned()
    } else {
        format!("/{}", clean(&state.query))
    };
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(prefix, Style::default().fg(theme.accent_system)),
            Span::styled(
                search,
                Style::default().fg(if state.searching {
                    theme.fuzzy_accent
                } else {
                    theme.text_secondary
                }),
            ),
        ]))
        .style(Style::default().bg(theme.bg_light)),
        area,
    );
}

fn render_timeline(
    frame: &mut Frame<'_>,
    area: Rect,
    data: &TraceData,
    state: &mut Explorer,
    theme: &Theme,
) {
    let title = format!(
        " Timeline · {}/{} ",
        state.list.selected().map_or(0, |index| index + 1),
        state.visible.len()
    );
    let block = panel(title, !state.detail_focus, theme);
    state.timeline_page = (block.inner(area).height as usize / 2).max(1);
    if state.visible.is_empty() {
        frame.render_widget(
            Paragraph::new("No matching events.\nEsc clears all filters.").block(block),
            area,
        );
        return;
    }
    let selected = state.list.selected().unwrap_or(0);
    let offset = state
        .list
        .offset()
        .min(selected)
        .max(selected.saturating_sub(state.timeline_page - 1));
    *state.list.offset_mut() = offset;
    // Build only the viewport, even for recordings with tens of thousands of events.
    let items: Vec<ListItem<'_>> = state
        .visible
        .iter()
        .enumerate()
        .skip(offset)
        .take(state.timeline_page)
        .filter_map(|(position, &index)| {
            let event = data.events.get(index)?;
            let turn_marker = position == 0
                || state
                    .visible_event(data, position - 1)
                    .and_then(|event| event.turn)
                    != event.turn;
            let turn = event
                .turn
                .map_or_else(|| "—".to_owned(), |turn| turn.to_string());
            let status = if is_error(event) { "!" } else { "·" };
            let lines = vec![
                Line::from(vec![
                    Span::styled(
                        format!("{status} {:04} ", event.index),
                        Style::default().fg(event_color(event, theme)),
                    ),
                    Span::styled(
                        clean(&event.title),
                        Style::default()
                            .fg(event_color(event, theme))
                            .add_modifier(Modifier::BOLD),
                    ),
                ]),
                Line::from(Span::styled(
                    format!(
                        "       {}T{turn}  {}  {}",
                        if turn_marker { "┌ " } else { "  " },
                        clean(&event.kind),
                        event.duration_ms.map_or_else(
                            || format!("+{}", duration(event.elapsed_ms)),
                            |ms| format!("Δ {}", duration(Some(ms)))
                        )
                    ),
                    Style::default().fg(theme.text_secondary),
                )),
            ];
            Some(ListItem::new(lines))
        })
        .collect();
    let mut window = ListState::default().with_selected(Some(selected - offset));
    frame.render_stateful_widget(
        List::new(items)
            .block(block)
            .highlight_style(Style::default().bg(theme.bg_highlight))
            .highlight_symbol("› "),
        area,
        &mut window,
    );
}

fn render_detail(
    frame: &mut Frame<'_>,
    area: Rect,
    data: &TraceData,
    state: &mut Explorer,
    theme: &Theme,
) {
    let block = panel(
        format!(
            " {} · {} ",
            state.tab_name(),
            if state.detail_focus {
                "focused"
            } else {
                "Tab to focus"
            }
        ),
        state.detail_focus,
        theme,
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height == 0 || inner.width == 0 {
        return;
    }
    let [tabs_area, lines_area, scroll_area] = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(u16::from(inner.height >= 3)),
            Constraint::Min(0),
            Constraint::Length(u16::from(inner.height >= 5)),
        ])
        .areas(inner);
    let names = if inner.width < 55 {
        vec!["1 Info", "2 Event", "3 I/O", "4 JSON", "5 Files"]
    } else {
        vec![
            "1 Overview",
            "2 Event",
            "3 Tool I/O",
            "4 Raw JSON",
            "5 Artifacts",
        ]
    };
    frame.render_widget(
        Tabs::new(names)
            .select(state.tab)
            .divider(" ")
            .style(Style::default().fg(theme.text_secondary))
            .highlight_style(
                Style::default()
                    .fg(theme.text_primary)
                    .bg(theme.bg_highlight)
                    .add_modifier(Modifier::BOLD),
            ),
        tabs_area,
    );
    let key = (state.selected(), state.tab, lines_area.width);
    if state.detail_key != Some(key) {
        let content = detail_content(data, state.selected(), state.tab);
        let width = lines_area.width.max(1) as usize;
        // Slice wrapped lines ourselves: Paragraph's u16 scroll would make long tool output unreachable.
        state.detail_lines = clean(&content)
            .lines()
            .flat_map(|line| {
                if line.is_empty() {
                    vec![String::new()]
                } else {
                    textwrap::wrap(line, width)
                        .into_iter()
                        .map(|line| line.into_owned())
                        .collect()
                }
            })
            .collect();
        state.detail_key = Some(key);
    }
    state.viewport_height = lines_area.height as usize;
    state.scroll = state.scroll.min(
        state
            .detail_lines
            .len()
            .saturating_sub(state.viewport_height),
    );
    let lines: Vec<Line<'_>> = state
        .detail_lines
        .iter()
        .skip(state.scroll)
        .take(state.viewport_height)
        .map(|line| Line::raw(line.as_str()))
        .collect();
    frame.render_widget(
        Paragraph::new(lines).style(Style::default().fg(theme.text_primary)),
        lines_area,
    );
    frame.render_widget(
        Paragraph::new(format!(
            " {}–{} / {} lines  ·  J/K scroll",
            if state.detail_lines.is_empty() {
                0
            } else {
                state.scroll + 1
            },
            (state.scroll + state.viewport_height).min(state.detail_lines.len()),
            state.detail_lines.len()
        ))
        .style(Style::default().fg(theme.gray)),
        scroll_area,
    );
}

fn detail_content(data: &TraceData, selected: Option<usize>, tab: usize) -> String {
    if tab == 0 {
        return overview(data);
    }
    if tab == 4 {
        let mut text = format!(
            "RECORDED ARTIFACTS · {}\n\nThese are captured snapshots; files are not executed or opened.\n",
            data.artifacts.len()
        );
        if data.artifacts.is_empty() {
            text.push_str("\nNo artifact snapshots were recorded.\n");
        }
        for artifact in &data.artifacts {
            text.push_str(&format!(
                "\n── {} ──\n{}\n",
                artifact.name,
                display_value(&artifact.content)
            ));
        }
        return text;
    }
    let Some(event) = selected.and_then(|index| data.events.get(index)) else {
        return "No event selected.\n\nPress Esc to clear filters, or 1 for the session overview."
            .to_owned();
    };
    if tab == 3 {
        return pretty(&event.raw);
    }
    if tab == 2 {
        let tools: Vec<&TraceTool> = data
            .tools
            .iter()
            .filter(|tool| {
                event.tool_call_id.as_deref() == Some(tool.id.as_str())
                    || tool.event_indices.contains(&event.index)
            })
            .collect();
        if tools.is_empty() {
            return "This event has no linked tool call.\n\nPress f to filter the timeline to tools.\nRaw JSON retains every recorded event field.".to_owned();
        }
        return tools.iter().map(|tool| format!(
            "{}\n\nCall ID     {}\nStatus      {}\nTurn        {}\nDuration    {}\nEvents      {}\n\nINPUT\n{}\n\nOUTPUT\n{}",
            tool.name, tool.id, tool.status, optional_number(tool.turn), duration(tool.duration_ms),
            tool.event_indices.iter().map(usize::to_string).collect::<Vec<_>>().join(", "),
            tool.input.as_ref().map_or_else(|| "Not recorded".to_owned(), display_value),
            tool.output.as_ref().map_or_else(|| "Not recorded (the call may be incomplete)".to_owned(), display_value)
        )).collect::<Vec<_>>().join("\n\n────────────────────\n\n");
    }
    format!(
        "{}\n\nEvent       {}\nKind        {}\nStatus      {}\nTurn        {}\nTimestamp   {}\nElapsed     {}\nDuration    {}\nSource      {}{}\nTool call   {}\n\nCONTENT\n{}",
        event.title,
        event.index,
        event.kind,
        event.status.as_deref().unwrap_or("Not recorded"),
        optional_number(event.turn),
        event.timestamp.as_deref().unwrap_or("Not recorded"),
        duration(event.elapsed_ms),
        duration(event.duration_ms),
        event.source,
        event
            .line
            .map_or_else(String::new, |line| format!(":{line}")),
        event.tool_call_id.as_deref().unwrap_or("—"),
        if event.text.is_empty() {
            "No text payload. Inspect Raw JSON for the complete event."
        } else {
            &event.text
        }
    )
}

fn overview(data: &TraceData) -> String {
    let summary = &data.summary;
    let mut text = format!(
        "SESSION\n\nTitle       {}\nSession     {}\nSource      {}\nModel       {}\nDirectory   {}\nCreated     {}\nUpdated     {}\nSchema      {}\n\nTOTALS\n\nEvents      {}\nTurns       {}\nTools       {}\nErrors      {}\nDuration    {}\nInput       {} tokens\nOutput      {} tokens\nCached      {} tokens\nTotal       {} tokens\n\nTURN TIMELINE\n",
        data.title,
        data.session_id,
        data.source,
        data.model.as_deref().unwrap_or("Not recorded"),
        data.cwd.as_deref().unwrap_or("Not recorded"),
        data.created_at.as_deref().unwrap_or("Not recorded"),
        data.updated_at.as_deref().unwrap_or("Not recorded"),
        data.schema_version,
        summary.event_count,
        summary.turn_count,
        summary.tool_count,
        summary.error_count,
        duration(summary.duration_ms),
        optional_number(summary.input_tokens),
        optional_number(summary.output_tokens),
        optional_number(summary.cached_input_tokens),
        optional_number(summary.total_tokens)
    );
    for turn in &data.turns {
        text.push_str(&format!(
            "\nTurn {} · {} · {} events · {}\n  Model: {}\n  Start: {}\n  End:   {}\n",
            turn.number,
            turn.status.as_deref().unwrap_or("unknown"),
            turn.event_count,
            duration(turn.duration_ms),
            turn.model.as_deref().unwrap_or("Not recorded"),
            turn.started_at.as_deref().unwrap_or("Not recorded"),
            turn.ended_at.as_deref().unwrap_or("Not recorded")
        ));
    }
    text.push_str("\nRECORDING NOTES\n\nOnly recorded information is shown. Missing values are not zero.\nReasoning is available only when included in the recording.\n");
    for warning in &data.warnings {
        text.push_str(&format!("\n• {warning}\n"));
    }
    text
}

fn duration(value: Option<u64>) -> String {
    match value {
        None => "—".to_owned(),
        Some(ms) if ms < 1_000 => format!("{ms} ms"),
        Some(ms) if ms < 60_000 => format!("{:.2} s", ms as f64 / 1_000.0),
        Some(ms) => format!("{}m {:.1}s", ms / 60_000, (ms % 60_000) as f64 / 1_000.0),
    }
}

fn optional_number(value: Option<u64>) -> String {
    value.map_or_else(|| "Not recorded".to_owned(), |value| value.to_string())
}

fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}

fn display_value(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| pretty(value))
}

fn clean(text: &str) -> String {
    // The escape parser treats tabs as controls; expand them first for readable code.
    strip_ansi_escapes::strip_str(text.replace('\t', "    "))
        .chars()
        .filter(|ch| !ch.is_control() || *ch == '\n')
        .collect()
}

fn render_help(frame: &mut Frame<'_>, area: Rect, theme: &Theme) {
    let width = area.width.min(76);
    let height = area.height.min(23);
    let popup = Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    );
    frame.render_widget(Clear, popup);
    let help = "READ A TRACE\n\n↑/↓ or j/k     Move in the focused pane\nTab / Enter    Switch timeline and details\n1–5 or h/l     Switch details view\n/              Search event text and raw fields\nf              Cycle event category\nt              Toggle selected turn filter\n[ / ]          Previous / next turn\ne              Next error (clears filters)\nEsc            Clear search and all filters\nJ / K          Scroll details from either pane\nPgUp / PgDn    Page in the focused pane\ng / G          First / last event or detail line\n?              Keyboard help\nq / Ctrl-C     Close the explorer\n\nNarrow terminals show one pane; Tab changes panes.\nAny key closes help.";
    frame.render_widget(
        Paragraph::new(help)
            .block(panel(" Trace explorer · keyboard ".to_owned(), true, theme))
            .style(Style::default().bg(theme.bg_light).fg(theme.text_primary)),
        popup,
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use serde_json::json;

    fn fixture() -> TraceData {
        serde_json::from_value(json!({
            "schema_version": 1, "source": "/tmp/trace", "session_id": "test-session",
            "title": "Find the failing command", "model": "grok", "cwd": "/work",
            "created_at": null, "updated_at": null,
            "summary": {"event_count": 4, "turn_count": 2, "tool_count": 1, "error_count": 1,
                "duration_ms": 1200, "input_tokens": 80, "output_tokens": 20,
                "cached_input_tokens": null, "total_tokens": 100},
            "events": [
                {"index": 0, "source": "agent.jsonl", "line": 1, "kind": "user_message", "title": "User message",
                    "text": "Inspect the build", "turn": 1, "raw": {"secret_field": "needle"}},
                {"index": 1, "source": "agent.jsonl", "line": 2, "kind": "tool_call", "title": "Run shell",
                    "text": "cargo test", "turn": 1, "tool_call_id": "tool-1", "raw": {"command": "cargo test"}},
                {"index": 2, "source": "agent.jsonl", "line": 3, "kind": "tool_result", "title": "Command failed",
                    "text": "missing Cargo.toml", "turn": 1, "tool_call_id": "tool-1", "status": "failed", "raw": {"exit_code": 1}},
                {"index": 3, "source": "agent.jsonl", "line": 4, "kind": "assistant_message", "title": "Assistant",
                    "text": "Use the workspace root", "turn": 2, "raw": {"message": "Use the workspace root"}}
            ],
            "turns": [{"number": 1, "model": "grok", "event_count": 3}, {"number": 2, "event_count": 1}],
            "tools": [{"id": "tool-1", "name": "shell", "turn": 1, "status": "failed",
                "input": {"command": "cargo test"}, "output": {"exit_code": 1, "stderr": "missing Cargo.toml"},
                "duration_ms": 42, "event_indices": [1, 2]}],
            "artifacts": [{"name": "config.json", "content": {"mode": "debug"}}],
            "warnings": ["Reasoning was not recorded"]
        })).expect("valid trace fixture")
    }

    fn press(state: &mut Explorer, data: &TraceData, code: KeyCode) {
        assert!(!state.key(data, KeyEvent::new(code, KeyModifiers::NONE)));
    }

    #[test]
    fn search_raw_fields_and_restore_cancelled_query() {
        let data = fixture();
        let mut state = Explorer::new(&data);
        press(&mut state, &data, KeyCode::Char('/'));
        for ch in "NEEDLE".chars() {
            press(&mut state, &data, KeyCode::Char(ch));
        }
        assert_eq!(state.visible, vec![0]);
        press(&mut state, &data, KeyCode::Enter);
        press(&mut state, &data, KeyCode::Char('/'));
        press(&mut state, &data, KeyCode::Char('x'));
        assert!(state.visible.is_empty());
        press(&mut state, &data, KeyCode::Esc);
        assert_eq!(state.visible, vec![0]);
        press(&mut state, &data, KeyCode::Esc);
        assert_eq!(state.visible.len(), 4);
    }

    #[test]
    fn navigation_filters_and_error_jump_keep_selection_valid() {
        let data = fixture();
        let mut state = Explorer::new(&data);
        press(&mut state, &data, KeyCode::Char(']'));
        assert_eq!(state.selected(), Some(3));
        press(&mut state, &data, KeyCode::Char('t'));
        assert_eq!(state.visible, vec![3]);
        press(&mut state, &data, KeyCode::Char('e'));
        assert_eq!(state.selected(), Some(2));
        assert_eq!(state.turn, None);
        assert_eq!(state.visible.len(), 4);
        press(&mut state, &data, KeyCode::Char('['));
        assert_eq!(state.selected(), Some(2)); // No earlier turn in the recording.
        press(&mut state, &data, KeyCode::End);
        press(&mut state, &data, KeyCode::Char('['));
        assert_eq!(state.selected(), Some(0));
        press(&mut state, &data, KeyCode::Char('f'));
        assert_eq!(state.visible, vec![0, 3]);
        press(&mut state, &data, KeyCode::Char('f'));
        assert!(state.visible.is_empty());
        press(&mut state, &data, KeyCode::Down);
        assert_eq!(state.selected(), None);
    }

    #[test]
    fn tool_event_raw_and_artifacts_preserve_debug_data() {
        let mut data = fixture();
        let tool = detail_content(&data, Some(2), 2);
        assert!(tool.contains("INPUT\n"));
        assert!(tool.contains("OUTPUT\n"));
        assert!(tool.contains("cargo test"));
        assert!(tool.contains("missing Cargo.toml"));
        assert!(detail_content(&data, Some(0), 3).contains("needle"));
        assert!(detail_content(&data, Some(0), 4).contains("config.json"));
        assert!(overview(&data).contains("Reasoning was not recorded"));
        assert!(detail_content(&data, Some(2), 1).contains("agent.jsonl:3"));
        data.tools.first_mut().unwrap().output = Some(json!("line one\nline two"));
        assert!(detail_content(&data, Some(2), 2).contains("OUTPUT\nline one\nline two"));
    }

    #[test]
    fn long_details_scroll_beyond_u16_line_limit() {
        let mut state = Explorer {
            detail_lines: vec![String::new(); 70_000],
            viewport_height: 20,
            ..Explorer::default()
        };
        state.scroll_detail(69_000);
        assert_eq!(state.scroll, 69_000);
        state.scroll_detail(isize::MAX);
        assert_eq!(state.scroll, 69_980);
        state.scroll_detail(isize::MIN);
        assert_eq!(state.scroll, 0);
    }

    fn screen(terminal: &Terminal<TestBackend>) -> String {
        terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect()
    }

    #[test]
    fn renders_full_and_narrow_terminals_and_empty_traces() {
        let data = fixture();
        for (width, height) in [(120, 32), (60, 18), (24, 8), (10, 3)] {
            let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
            let mut state = Explorer::new(&data);
            terminal
                .draw(|frame| render(frame, &data, &mut state, &Theme::default()))
                .unwrap();
            if width >= 60 {
                assert!(screen(&terminal).contains("Timeline"));
            }
            state.detail_focus = true;
            state.tab = 2;
            state.select(2);
            terminal
                .draw(|frame| render(frame, &data, &mut state, &Theme::default()))
                .unwrap();
            if width >= 60 {
                assert!(screen(&terminal).contains("tool-1"));
            }
            if width == 24 {
                assert!(screen(&terminal).contains("shell"));
            }
            state.help = true;
            terminal
                .draw(|frame| render(frame, &data, &mut state, &Theme::default()))
                .unwrap();
        }
        let mut data = data;
        data.events.clear();
        let mut terminal = Terminal::new(TestBackend::new(120, 25)).unwrap();
        let mut state = Explorer::new(&data);
        terminal
            .draw(|frame| render(frame, &data, &mut state, &Theme::default()))
            .unwrap();
        assert!(screen(&terminal).contains("No matching events"));
    }

    #[test]
    fn recorded_terminal_sequences_cannot_change_the_terminal() {
        assert_eq!(
            clean("hello\u{1b}[31mred\u{1b}[0m\u{7}\n\tworld"),
            "hellored\n    world"
        );
    }
}
