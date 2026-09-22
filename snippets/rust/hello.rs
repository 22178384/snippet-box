//! A stdin -> stdout line filter, the shape most CLI tools start from.
//!
//! Reads lines, filters and uppercases them, counts them, writes to stdout.
//! Compile and run:
//!
//!     rustc hello.rs -o hello
//!     printf 'alpha\nbeta\ngamma\n' | ./hello -f be
//!
//! `cargo` isn't needed; there are no dependencies. Uses `let-else`, so Rust
//! 1.65+.

use std::env;
use std::io::{self, BufRead, Write};
use std::process::ExitCode;

struct Args {
    filter: Option<String>,
    upper: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args { filter: None, upper: false };
    let mut argv = env::args().skip(1);

    while let Some(flag) = argv.next() {
        match flag.as_str() {
            "-f" | "--filter" => {
                // let-else: the cleanest way to bail when the next token is
                // missing. Older Rust needed a match + unreachable!().
                let Some(value) = argv.next() else {
                    return Err(format!("{flag} needs a value"));
                };
                args.filter = Some(value);
            }
            "-u" | "--upper" => args.upper = true,
            "-h" | "--help" => {
                println!("usage: hello [-f FILTER] [-u]");
                std::process::exit(0);
            }
            other => return Err(format!("unknown flag: {other}")),
        }
    }
    Ok(args)
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(msg) => {
            eprintln!("error: {msg}");
            return ExitCode::FAILURE;
        }
    };

    let stdin = io::stdin();
    let stdout = io::stdout();
    // BufWriter matters: writing to a locked stdout line by line is slow
    // because each write is a syscall.
    let mut out = io::BufWriter::new(stdout.lock());

    let mut kept: usize = 0;
    let mut total: usize = 0;

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                eprintln!("error reading stdin: {e}");
                return ExitCode::FAILURE;
            }
        };
        total += 1;

        if let Some(needle) = &args.filter {
            if !line.contains(needle.as_str()) {
                continue;
            }
        }

        let rendered = if args.upper { line.to_uppercase() } else { line };
        if let Err(e) = writeln!(out, "{rendered}") {
            // EPIPE happens when the downstream process (e.g. `head`) closes
            // the pipe. That's normal, not an error worth a stack of noise.
            if e.kind() == io::ErrorKind::BrokenPipe {
                return ExitCode::SUCCESS;
            }
            eprintln!("error writing stdout: {e}");
            return ExitCode::FAILURE;
        }
        kept += 1;
    }

    if let Err(e) = out.flush() {
        eprintln!("error flushing: {e}");
        return ExitCode::FAILURE;
    }

    eprintln!("kept {kept} of {total} lines");
    ExitCode::SUCCESS
}
