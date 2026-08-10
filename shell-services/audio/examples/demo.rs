//! Prints what the crate believes, in the daemon's own NDJSON layout, so this and
//! `audiod` can be diffed by eye.
//!
//!     cargo run -p koompi-audio --example demo [seconds]

use std::process::ExitCode;
use std::time::Duration;

use koompi_audio::{AudioService, Message};
use koompi_service::{PollRate, Service};

#[tokio::main]
async fn main() -> ExitCode {
    let seconds: Option<u64> = std::env::args().nth(1).and_then(|arg| arg.parse().ok());

    let service = match AudioService::start(PollRate::NORMAL) {
        Ok(service) => service,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };
    eprintln!("audiod: {}", service.binary().display());

    let mut states = service.subscribe();
    if let Err(error) = service.ready().await {
        eprintln!("{error}");
        return ExitCode::FAILURE;
    }

    if let Some(hello) = service.status().hello {
        println!("{}", Message::Hello(hello).to_line());
    }
    let initial = states.borrow_and_update().clone();
    println!("{}", Message::State(initial).to_line());

    let stream = async {
        while states.changed().await.is_ok() {
            let state = states.borrow_and_update().clone();
            println!("{}", Message::State(state).to_line());
        }
    };

    match seconds {
        Some(seconds) => {
            let _ = tokio::time::timeout(Duration::from_secs(seconds), stream).await;
        }
        None => stream.await,
    }
    ExitCode::SUCCESS
}
