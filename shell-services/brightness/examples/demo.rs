//! Prints every panel the seat has, its raw and normalised value and which backend
//! drives it, then follows changes including the ones made outside the shell.
//!
//! `--set` and `--set-raw` are the only paths here that write anything.

use koompi_brightness::{BrightnessService, BrightnessState};
use koompi_service::{PollRate, Service};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let service = BrightnessService::connect(PollRate::NORMAL).await?;

    match args.first().map(String::as_str) {
        Some(flag @ ("--set" | "--set-raw")) => {
            let id = args.get(1).ok_or("usage: demo --set <panel> <value>")?;
            let value: f64 = args
                .get(2)
                .ok_or("usage: demo --set <panel> <value>")?
                .parse()?;

            if flag == "--set" {
                service.set(id, value / 100.0)?;
            } else {
                service.set_raw(id, value as u32)?;
            }

            let mut rx = service.subscribe();
            let _ = tokio::time::timeout(std::time::Duration::from_secs(3), rx.changed()).await;
            print(&service.state());
        }
        Some("--once") => print(&service.state()),
        Some(other) => return Err(format!("unknown argument {other}").into()),
        None => {
            print(&service.state());
            let mut rx = service.subscribe();
            while rx.changed().await.is_ok() {
                println!("\n--- changed ---");
                print(&rx.borrow_and_update());
            }
        }
    }

    Ok(())
}

fn print(state: &BrightnessState) {
    println!("panels: {}", state.panels.len());
    for panel in &state.panels {
        println!(
            "  {} connector={} backend={:?} raw={}/{} percent={:.1}% bus={}",
            panel.id,
            panel.connector.as_deref().unwrap_or("-"),
            panel.backend,
            panel.raw,
            panel.raw_max,
            panel.percent(),
            panel
                .bus
                .map(|bus| format!("/dev/i2c-{bus}"))
                .unwrap_or_else(|| "-".into()),
        );
    }
    println!(
        "external (ddc) panels: {}",
        state
            .panels
            .iter()
            .filter(|panel| panel.bus.is_some())
            .count()
    );
}
