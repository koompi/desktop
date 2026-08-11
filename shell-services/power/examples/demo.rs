//! Reads this seat and then follows it. Nothing here writes.

use std::time::Instant;

use koompi_power::{Battery, PowerConfig, PowerService, PowerState};
use koompi_service::Service;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let service = PowerService::connect(PowerConfig::default()).await?;
    let started = Instant::now();

    print_state(&service.state());
    print_unavailable_path().await;

    println!("\n-- following, ^C to stop --");
    let mut rx = service.subscribe();
    while rx.changed().await.is_ok() {
        let state = rx.borrow_and_update().clone();
        let Some(battery) = state.primary() else {
            continue;
        };
        println!(
            "[{:>6.1}s] state={:<14} plugged_in={:<5} on_battery={:<5} percentage={:>5.1}% rate={:>6.3}W to_empty={:>5}s to_full={:>5}s poll_rate=x{}",
            started.elapsed().as_secs_f64(),
            battery.state.as_str(),
            state.plugged_in,
            state.on_battery,
            battery.percentage,
            battery.energy_rate,
            battery.time_to_empty,
            battery.time_to_full,
            state.poll_rate.factor(),
        );
    }
    Ok(())
}

fn print_state(state: &PowerState) {
    println!("seat");
    println!("  on_battery       {}", state.on_battery);
    println!("  plugged_in       {}", state.plugged_in);
    println!("  poll_rate        x{}", state.poll_rate.factor());

    match &state.profiles {
        Some(profiles) => {
            println!(
                "  active_profile   {}",
                profiles.active.map_or("<unmodelled>", |p| p.as_str())
            );
            let available: Vec<&str> = profiles.available.iter().map(|p| p.as_str()).collect();
            println!("  profiles         {}", available.join(", "));
            println!(
                "  degraded         {}",
                profiles.degraded.as_deref().unwrap_or("no")
            );
        }
        None => println!("  active_profile   <unavailable: no power-profiles-daemon>"),
    }

    match &state.display {
        Some(battery) => print_battery("display device", battery),
        None => println!("\ndisplay device is not a battery, this seat draws no charge state"),
    }
    for battery in &state.batteries {
        print_battery(&format!("battery {}", battery.native_path), battery);
    }
}

fn print_battery(title: &str, battery: &Battery) {
    println!("\n{title}  ({})", battery.path);
    println!("  native_path      {}", battery.native_path);
    println!("  present          {}", battery.present);
    println!("  state            {}", battery.state.as_str());
    println!("  charging         {}", battery.charging);
    println!("  percentage       {:.1}%", battery.percentage);
    println!("  low              {}", battery.low);
    println!("  critical         {}", battery.critical);
    println!("  full             {}", battery.full);
    println!("  warning_level    {}", battery.warning.as_str());
    println!("  energy           {:.2} Wh", battery.energy);
    println!("  energy_full      {:.2} Wh", battery.energy_full);
    println!("  energy_full_des  {:.2} Wh", battery.energy_full_design);
    println!("  energy_rate      {:.3} W", battery.energy_rate);
    println!(
        "  time_to_empty    {}s ({:.1} min)",
        battery.time_to_empty,
        battery.time_to_empty as f64 / 60.0
    );
    println!("  time_to_full     {}s", battery.time_to_full);
    println!(
        "  health           {}",
        battery
            .health
            .map_or("<none reported>".to_owned(), |h| format!("{h:.4}%"))
    );
    println!(
        "  cycle_count      {}",
        battery
            .cycle_count
            .map_or("<none reported>".to_owned(), |c| c.to_string())
    );
    println!("  icon_name        {}", battery.icon_name);
    println!(
        "  threshold        supported={} enabled={} start={}% end={}%",
        battery.threshold.supported,
        battery.threshold.enabled,
        battery.threshold.start,
        battery.threshold.end
    );
}

/// `PowerSaving.qml:53` never opens the daemon while the feature is off. Same gate
/// here, and the read that follows says so rather than failing.
async fn print_unavailable_path() {
    let config = PowerConfig {
        power_profiles: false,
        ..PowerConfig::default()
    };
    let Ok(service) = PowerService::connect(config).await else {
        return;
    };
    println!("\nwith power_profiles off, no daemon is opened:");
    match service.profiles() {
        Ok(_) => println!("  profiles()  unexpectedly answered"),
        Err(error) => println!("  profiles()  {error}"),
    }
}
