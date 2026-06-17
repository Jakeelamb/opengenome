mod cli;
mod confirmation;
mod file_picker;
mod filter;
mod float;
mod floating_text;
mod hint;
mod logo;
mod root;
mod running_command;
mod setup_wizard;
mod state;
mod system_info;
mod theme;

#[cfg(feature = "tips")]
mod tips;

use crate::cli::Args;
use clap::Parser;
use ratatui::{
    backend::CrosstermBackend,
    crossterm::{
        event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
        style::ResetColor,
        terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
        ExecutableCommand,
    },
    Terminal,
};
use running_command::TERMINAL_UPDATED;
use state::AppState;
use std::{
    io::{stdout, Result, Stdout},
    sync::atomic::Ordering,
    time::{Duration, Instant},
};

const UI_TICK_RATE: Duration = Duration::from_millis(100);

fn main() -> Result<()> {
    let args = Args::parse();

    stdout().execute(EnterAlternateScreen)?;
    if args.mouse {
        stdout().execute(EnableMouseCapture)?;
    }

    let mut state = AppState::new(args.clone());

    enable_raw_mode()?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout()))?;
    terminal.clear()?;

    run(&mut terminal, &mut state)?;

    // restore terminal
    disable_raw_mode()?;
    terminal.backend_mut().execute(LeaveAlternateScreen)?;
    if args.mouse {
        terminal.backend_mut().execute(DisableMouseCapture)?;
    }
    terminal.backend_mut().execute(ResetColor)?;
    terminal.show_cursor()?;

    Ok(())
}

fn run(terminal: &mut Terminal<CrosstermBackend<Stdout>>, state: &mut AppState) -> Result<()> {
    terminal.draw(|frame| state.draw(frame))?;
    let mut last_tick = Instant::now();

    loop {
        let poll_timeout = UI_TICK_RATE
            .checked_sub(last_tick.elapsed())
            .unwrap_or(Duration::ZERO);
        let mut should_draw = false;

        // It's guaranteed that the `read()` won't block when the `poll()`
        // function returns `true`
        if event::poll(poll_timeout)? {
            match event::read()? {
                Event::Key(key) => {
                    if key.kind == KeyEventKind::Press || key.kind == KeyEventKind::Repeat {
                        if !state.handle_key(&key) {
                            return Ok(());
                        }
                        should_draw = true;
                    }
                }
                Event::Mouse(mouse_event) if !state.handle_mouse(&mouse_event) => {
                    return Ok(());
                }
                _ => should_draw = true,
            }
        }

        if TERMINAL_UPDATED
            .compare_exchange(true, false, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            should_draw = true;
        }

        if last_tick.elapsed() >= UI_TICK_RATE {
            last_tick = Instant::now();
            should_draw = true;
        }

        if should_draw {
            terminal.draw(|frame| state.draw(frame))?;
        }
    }
}
