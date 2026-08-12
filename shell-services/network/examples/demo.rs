//! Reads this seat and then follows it.
//!
//! `--nmcli` prints the network list in the terse form of
//! `nmcli -c no -g ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY d w`, the command at
//! `Network.qml:267`, so the two can be diffed directly.
//!
//! `--scan` fires `RequestScan` first. That is the only write this binary makes without
//! being asked, and the shell already fires it from a button.
//!
//! `--connect <ssid> [passphrase]` takes the radio off whatever it is on, so it is opt-in
//! and never runs from `tests/run.sh`. It is the only way to exercise the connect path:
//! `AddAndActivateConnection` returns while the attempt is still in flight, so the thing
//! worth checking is that the verdict printed here is NetworkManager's and not the call's.
//! With a wrong passphrase it must refuse and leave no profile behind:
//!
//! ```text
//! cargo run -p koompi-network --example demo -- --connect "Some Cafe" wrong-on-purpose
//! nmcli -t -f NAME connection show | grep -c '^Some Cafe$'   # unchanged
//! ```

use std::time::Instant;

use koompi_network::{AccessPoint, NetworkService, NetworkState, Refresh};
use koompi_service::{Error, PollRate, Service};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let terse = args.iter().any(|a| a == "--nmcli");
    let scan = args.iter().any(|a| a == "--scan");
    let trace = args.iter().any(|a| a == "--trace");
    let connect = args.iter().position(|a| a == "--connect");

    let network = NetworkService::connect(PollRate::NORMAL).await?;

    if let Some(at) = connect {
        let ssid = args.get(at + 1).ok_or("--connect needs an ssid")?;
        let passphrase = args.get(at + 2).map(String::as_str);
        return probe_connect(&network, ssid, passphrase).await;
    }

    if terse {
        for line in nmcli_lines(&network.state()) {
            println!("{line}");
        }
        return Ok(());
    }

    print_state(&network.state());
    print_unavailable_path().await;

    if scan {
        println!("\nRequestScan ...");
        match network.request_scan().await {
            Ok(()) => println!("  accepted, scanning={}", network.state().wifi.scanning),
            Err(error) => println!("  {error}"),
        }
    }

    println!("\n-- following, ^C to stop --");
    let started = Instant::now();

    if trace {
        let mut refreshes = network.refreshes();
        tokio::spawn(async move {
            while let Ok(refresh) = refreshes.recv().await {
                println!(
                    "[{:>7.1}s] read {}",
                    started.elapsed().as_secs_f64(),
                    what(refresh)
                );
            }
        });
    }

    let mut rx = network.subscribe();
    while rx.changed().await.is_ok() {
        let state = rx.borrow_and_update().clone();
        println!(
            "[{:>7.1}s] {:<12} {:<8} name={:<18} strength={:>3} bssid={:<17} aps={:>2} scanning={:<5} connecting={:<5} bitrate={}",
            started.elapsed().as_secs_f64(),
            state.wifi.status.as_str(),
            state.connectivity.as_str(),
            state.network_name(),
            state.network_strength(),
            state
                .wifi
                .active
                .as_ref()
                .map_or("-", |ap| ap.hw_address.as_str()),
            state.wifi.networks.len(),
            state.wifi.scanning,
            state.wifi.connecting,
            state.wifi.bitrate,
        );
    }
    Ok(())
}

/// The elapsed time is the point. A connect that answers instantly answered before
/// NetworkManager had authenticated, which is the bug this path was written for.
async fn probe_connect(
    network: &NetworkService,
    ssid: &str,
    passphrase: Option<&str>,
) -> Result<(), Box<dyn std::error::Error>> {
    let state = network.state();
    let ap = state
        .wifi
        .networks
        .iter()
        .find(|ap| ap.ssid.to_lossy() == ssid)
        .ok_or_else(|| format!("{ssid} is not in range"))?;

    println!(
        "connecting to {ssid} ({}) {}",
        ap.security.label(),
        match passphrase {
            Some(_) => "with a passphrase",
            None => "with no passphrase: a saved profile or nothing",
        }
    );

    let started = Instant::now();
    let outcome = network.connect_to(ap, passphrase).await;
    let elapsed = started.elapsed().as_secs_f64();

    match outcome {
        Ok(active) => println!("  activated after {elapsed:.1}s: {active}"),
        Err(error) => println!("  refused after {elapsed:.1}s: {error}"),
    }
    Ok(())
}

fn print_state(state: &NetworkState) {
    println!("NetworkManager {}", state.version);
    println!("  available        {}", state.available);
    println!("  state            {}", state.state.as_str());
    println!("  connectivity     {}", state.connectivity.as_str());
    println!("  captive_portal   {}", state.captive_portal());
    println!("  connected        {}", state.connected());
    println!("  ethernet         {}", state.ethernet());
    println!("  network_name     {}", state.network_name());
    println!("  network_strength {}", state.network_strength());
    println!("  poll_rate        x{}", state.poll_rate.factor());

    println!("\nwifi");
    println!("  present          {}", state.wifi.present);
    println!("  enabled          {}", state.wifi.enabled);
    println!("  status           {}", state.wifi.status.as_str());
    println!("  scanning         {}", state.wifi.scanning);
    println!("  connecting       {}", state.wifi.connecting);
    println!(
        "  connect_target   {}",
        state
            .wifi
            .connect_target
            .as_ref()
            .map_or("<none>".into(), |s| s.to_lossy().into_owned())
    );
    println!("  interface        {}", state.wifi.interface);
    println!("  device_state     {}", state.wifi.device_state.as_str());
    println!("  hw_address       {}", state.wifi.hw_address);
    println!("  bitrate          {} kbit/s", state.wifi.bitrate);
    println!("  last_scan        {} ms boottime", state.wifi.last_scan);

    match &state.wifi.active {
        Some(ap) => {
            println!("\nassociated access point  ({})", ap.path);
            println!("  ssid             {}", ap.ssid.to_lossy());
            println!("  ssid bytes       {:?}", ap.ssid.as_bytes());
            println!("  utf8             {}", ap.ssid.is_utf8());
            println!("  bssid            {}", ap.hw_address);
            println!("  strength         {}", ap.strength);
            println!("  frequency        {} MHz ({} GHz band)", ap.frequency, ap.band_ghz());
            println!("  bandwidth        {} MHz", ap.bandwidth);
            println!("  max_bitrate      {} kbit/s", ap.max_bitrate);
            println!(
                "  security         {}  (flags={} wpa={} rsn={})",
                ap.security.label(),
                ap.security.flags,
                ap.security.wpa,
                ap.security.rsn
            );
            println!("  wants_psk        {}", ap.security.wants_psk());
            println!("  enterprise       {}", ap.security.enterprise());
        }
        None => println!("\nno associated access point"),
    }

    println!("\nnetworks in range, one row per bssid ({})", state.wifi.networks.len());
    println!(
        "  {:<6} {:>6} {:>9} {:<24} {:<19} {:<8} SECURITY",
        "ACTIVE", "SIGNAL", "FREQ", "SSID", "BSSID", "UTF8"
    );
    for ap in &state.wifi.networks {
        println!(
            "  {:<6} {:>6} {:>5} MHz {:<24} {:<19} {:<8} {}",
            if ap.active { "yes" } else { "no" },
            ap.strength,
            ap.frequency,
            ap.ssid.to_lossy(),
            ap.hw_address,
            ap.ssid.is_utf8(),
            ap.security.label(),
        );
    }

    let by_ssid = state.wifi.networks_by_ssid();
    println!(
        "\nthe deduped view Network.qml:24 publishes: {} ssids from {} radios",
        by_ssid.len(),
        state.wifi.networks.len()
    );

    println!("\nwired devices ({})", state.wired.len());
    for wired in &state.wired {
        println!(
            "  {:<12} state={:<12} carrier={:<5} speed={} Mbit/s  {}",
            wired.device.interface,
            wired.device.state.as_str(),
            wired.carrier,
            wired.speed,
            wired.hw_address
        );
    }
    if state.wired.is_empty() {
        println!("  <none: this seat has no Device.Wired>");
    }

    println!("\nactive connections ({})", state.active_connections.len());
    for connection in &state.active_connections {
        println!(
            "  {:<24} {:<18} {:<12} default={:<5} vpn={:<5} {}",
            connection.id,
            connection.kind,
            connection.state.as_str(),
            connection.default_route,
            connection.vpn,
            connection.settings_path
        );
    }
    println!(
        "\nprimary connection  {}",
        state
            .primary
            .as_ref()
            .map_or("<none>".to_owned(), |c| format!("{} ({})", c.id, c.path))
    );
}

/// `nmcli -c no -g ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY d w`, field for field.
/// nmcli's terse output escapes `:` and `\` in every field.
fn nmcli_lines(state: &NetworkState) -> Vec<String> {
    state.wifi.networks.iter().map(nmcli_line).collect()
}

fn nmcli_line(ap: &AccessPoint) -> String {
    [
        if ap.active { "yes" } else { "no" }.to_owned(),
        ap.strength.to_string(),
        format!("{} MHz", ap.frequency),
        ap.ssid.to_lossy().into_owned(),
        ap.hw_address.clone(),
        ap.security.label(),
    ]
    .iter()
    .map(|field| escape(field))
    .collect::<Vec<_>>()
    .join(":")
}

/// Which reads a coalesced burst of signals turned into. Everything absent from the
/// line was left alone.
fn what(refresh: Refresh) -> String {
    let named = [
        ("manager", refresh.manager),
        ("devices", refresh.devices),
        ("wifi-device", refresh.wifi),
        ("wired", refresh.wired),
        ("ap-list", refresh.access_points),
        ("one-ap", refresh.access_point),
        ("active-connections", refresh.active),
    ];
    named
        .iter()
        .filter(|(_, on)| *on)
        .map(|(name, _)| *name)
        .collect::<Vec<_>>()
        .join(" ")
}

fn escape(field: &str) -> String {
    field.replace('\\', "\\\\").replace(':', "\\:")
}

/// A seat with no NetworkManager is a working seat. The session bus has no such name on
/// it, which is the same answer the crate gives on a machine that never installed it.
async fn print_unavailable_path() {
    let Ok(session) = zbus::Connection::session().await else {
        return;
    };
    println!("\nagainst a bus with no NetworkManager on it:");
    match NetworkService::with_connection(session, PollRate::NORMAL).await {
        Ok(_) => println!("  connect()  unexpectedly answered"),
        Err(error @ Error::Unavailable(_)) => println!("  connect()  {error}"),
        Err(error) => println!("  connect()  {error}"),
    }
}
