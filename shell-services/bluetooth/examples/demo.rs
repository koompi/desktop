//! Prints the seat's adapters, its rfkill switches and every device BlueZ knows, then
//! follows the bus.
//!
//! `--power on|off` is the only path here that writes anything.

use koompi_bluetooth::{BluetoothService, BluetoothState};
use koompi_service::Service;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let service = BluetoothService::connect().await?;

    match args.first().map(String::as_str) {
        Some("--power") => {
            let powered = match args.get(1).map(String::as_str) {
                Some("on") => true,
                Some("off") => false,
                _ => return Err("usage: demo --power on|off".into()),
            };
            service.set_powered(powered).await?;
            // BlueZ answers the property write before the controller has finished, and
            // the state below should be the one the bus ended up in.
            let mut rx = service.subscribe();
            let _ = tokio::time::timeout(std::time::Duration::from_secs(3), async {
                while rx.borrow().powered() != powered {
                    if rx.changed().await.is_err() {
                        break;
                    }
                }
            })
            .await;
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

fn print(state: &BluetoothState) {
    println!("available: {}", state.available());

    println!("adapters: {}", state.adapters.len());
    for adapter in &state.adapters {
        println!(
            "  {} {} address={} name={} alias={} powered={} power_state={:?} discoverable={} discovering={} pairable={}",
            adapter.id,
            adapter.path,
            adapter.address,
            adapter.name,
            adapter.alias,
            adapter.powered,
            adapter.power_state,
            adapter.discoverable,
            adapter.discovering,
            adapter.pairable,
        );
    }

    println!("rfkill: {} switches", state.rfkill.entries.len());
    for entry in &state.rfkill.entries {
        println!(
            "  {} {} kind={:?} soft={} hard={}",
            entry.index,
            entry.name.as_deref().unwrap_or("?"),
            entry.kind,
            entry.soft_blocked,
            entry.hard_blocked,
        );
    }
    println!(
        "rfkill bluetooth: soft_blocked={} hard_blocked={}",
        state.rfkill.soft_blocked(),
        state.rfkill.hard_blocked(),
    );

    println!("devices: {}", state.devices.len());
    for device in &state.devices {
        println!(
            "  {} address={} name={} alias={} paired={} trusted={} connected={} blocked={} icon={} rssi={} battery={}",
            device.path,
            device.address,
            device.name.as_deref().unwrap_or("-"),
            device.alias,
            device.paired,
            device.trusted,
            device.connected,
            device.blocked,
            device.icon.as_deref().unwrap_or("-"),
            device
                .rssi
                .map(|rssi| rssi.to_string())
                .unwrap_or_else(|| "-".into()),
            device
                .battery
                .map(|battery| format!("{battery}%"))
                .unwrap_or_else(|| "-".into()),
        );
    }
}
