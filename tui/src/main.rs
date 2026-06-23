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
mod setup_status;
mod setup_wizard;
mod state;
mod system_info;
mod theme;

#[cfg(feature = "tips")]
mod tips;

use crate::cli::Args;
use clap::Parser;
use opengenome_core::Command as OpenGenomeCommand;
use ratatui::{
    backend::CrosstermBackend,
    crossterm::{
        event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
        style::ResetColor,
        terminal::{
            self, disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
        },
        ExecutableCommand,
    },
    Terminal,
};
use running_command::TERMINAL_UPDATED;
use state::AppState;
use std::{
    io::{self, stdout, ErrorKind, IsTerminal, Result, Stdout},
    process::{Command as ProcessCommand, Stdio},
    sync::atomic::Ordering,
    time::{Duration, Instant},
};

const UI_TICK_RATE: Duration = Duration::from_millis(100);

fn main() -> Result<()> {
    let args = Args::parse();

    if args.demo_output {
        return run_command_sequence(&["Try sample data", "Explain my results"]);
    }

    if args.human_validation_output {
        return run_command_sequence(&["Run human validation dataset", "Explain my results"]);
    }

    ensure_interactive_terminal()?;

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

fn ensure_interactive_terminal() -> Result<()> {
    if !io::stdin().is_terminal() || !stdout().is_terminal() {
        return Err(io::Error::new(
            ErrorKind::Unsupported,
            "Open Genome TUI needs an interactive terminal. For the bundled demo output bundle, run `cargo run -p opengenome_tui -- --demo-output`.",
        ));
    }

    let (cols, rows) = terminal::size()?;
    if cols == 0 || rows == 0 {
        return Err(io::Error::new(
            ErrorKind::Unsupported,
            "Open Genome TUI cannot draw because this terminal reports size 0x0. Run from a real terminal, or use `cargo run -p opengenome_tui -- --demo-output` for the bundled demo output bundle.",
        ));
    }

    Ok(())
}

fn run_command_sequence(command_names: &[&str]) -> Result<()> {
    let tabs = opengenome_core::get_tabs(false);
    for command_name in command_names {
        let command = tabs
            .iter()
            .flat_map(|tab| tab.tree.root().descendants())
            .find_map(|node| {
                let value = node.value();
                (value.name == *command_name).then(|| value.command.clone())
            })
            .ok_or_else(|| {
                io::Error::new(
                    ErrorKind::NotFound,
                    format!("Could not find bundled command: {command_name}"),
                )
            })?;

        run_shell_command(command_name, &command)?;
    }

    Ok(())
}

fn run_shell_command(name: &str, command: &OpenGenomeCommand) -> Result<()> {
    let status = match command {
        OpenGenomeCommand::Raw(script) => ProcessCommand::new("sh")
            .arg("-c")
            .arg(script)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()?,
        OpenGenomeCommand::LocalFile {
            executable, args, ..
        } => ProcessCommand::new(executable)
            .args(args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()?,
        OpenGenomeCommand::None => {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                format!("Bundled command is not runnable: {name}"),
            ));
        }
    };

    if status.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!(
            "Bundled command failed: {name} ({status})"
        )))
    }
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
