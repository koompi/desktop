//! Every player on this bus, the one the priority rule chose, then the changes.
//!
//! `--playerctl` prints one line per player in the shape of `playerctl -a status` so the
//! two can be diffed directly.
//!
//! Every line in the follow section is stamped with the seconds since start. That stamp
//! is the evidence for the poll being gone: with a track playing and then paused, nothing
//! lands on a fixed cadence, because nothing here has a timer.

use std::time::Instant;

use koompi_mpris::{ChoiceReason, MprisConfig, MprisEvent, MprisService, MprisState, Player};
use koompi_service::Service;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let terse = args.iter().any(|a| a == "--playerctl");
    let once = args.iter().any(|a| a == "--once");

    let mpris = MprisService::connect(MprisConfig::default()).await?;
    let state = mpris.state();

    if terse {
        for player in &state.players {
            println!("{} {}", player.suffix(), player.playback_status.as_str());
        }
        return Ok(());
    }

    print_state(&state);

    if let Some(active) = state.active_player() {
        // The player's own answer, next to ours. No subprocess, no timer: one Get,
        // because this line asked for it.
        match mpris.read_position(&active.bus_name).await {
            Ok(read) => println!(
                "\nPosition read back over the bus: {} us, interpolated {} us, drift {} us",
                read,
                active.position_now(),
                (read - active.position_now()).abs()
            ),
            Err(error) => println!("\nPosition read back over the bus: {error}"),
        }
    }

    if once {
        return Ok(());
    }

    println!("\n-- following, ^C to stop --");
    let started = Instant::now();

    let mut events = mpris.events();
    tokio::spawn(async move {
        while let Ok(event) = events.recv().await {
            println!("[{:>7.3}s] {}", started.elapsed().as_secs_f64(), describe(&event));
        }
    });

    let mut rx = mpris.subscribe();
    while rx.changed().await.is_ok() {
        let state = rx.borrow_and_update().clone();
        match state.active_player() {
            Some(player) => println!(
                "[{:>7.3}s] state active={} why={} {} pos={} anchor={} advancing={} title={:?}",
                started.elapsed().as_secs_f64(),
                player.suffix(),
                state.reason.as_str(),
                player.playback_status.as_str(),
                clock(player.position_now()),
                clock(player.position.position_us),
                player.position.advancing,
                player.metadata.title.as_deref().unwrap_or(""),
            ),
            None => println!(
                "[{:>7.3}s] state no player on the bus",
                started.elapsed().as_secs_f64()
            ),
        }
    }
    Ok(())
}

fn print_state(state: &MprisState) {
    println!("players on this bus: {}", state.players.len());
    println!(
        "active: {} ({})",
        state.active.as_deref().unwrap_or("<none>"),
        state.reason.as_str()
    );
    if state.reason == ChoiceReason::Nothing {
        println!("\nnothing exports org.mpris.MediaPlayer2 on this session bus.");
    }
    println!("poll_rate: x{}", state.poll_rate.factor());

    for player in &state.players {
        let mark = if state.active.as_deref() == Some(player.bus_name.as_str()) {
            "=>"
        } else {
            "  "
        };
        println!("\n{mark} {}", player.bus_name);
        println!("     identity       {}", player.identity);
        println!("     desktop_entry  {}", player.desktop_entry);
        println!("     status         {}", player.playback_status.as_str());
        println!(
            "     shadowed       {}",
            player.shadowed.map_or("no", |s| s.as_str())
        );
        println!("     can_quit       {}", player.can_quit);
        println!("     can_raise      {}", player.can_raise);

        let metadata = &player.metadata;
        println!("     title          {:?}", metadata.title.as_deref().unwrap_or(""));
        println!("     artist         {:?}", metadata.artist());
        println!("     album          {:?}", metadata.album.as_deref().unwrap_or(""));
        println!("     art_url        {}", metadata.art_url.as_deref().unwrap_or("<none>"));
        println!("     xesam:url      {}", metadata.url.as_deref().unwrap_or("<none>"));
        println!("     track_id       {}", metadata.track_id.as_deref().unwrap_or("<none>"));
        println!(
            "     length         {}",
            metadata.length_us.map_or("<none>".into(), |l| format!(
                "{} us ({})",
                l,
                clock(l)
            ))
        );
        println!(
            "     undecoded keys {}",
            if metadata.undecoded.is_empty() {
                "<none>".to_owned()
            } else {
                metadata.undecoded.join(" ")
            }
        );

        println!(
            "     position       {} interpolated, anchor {} taken {:.3}s ago, advancing={} rate={}",
            clock(player.position_now()),
            clock(player.position.position_us),
            player.position.read_at.elapsed().as_secs_f64(),
            player.position.advancing,
            player.rate,
        );
        println!(
            "     overran        {} (slack {}s)",
            player.overran(Instant::now(), koompi_mpris::OVERRUN_SLACK.as_micros() as i64),
            koompi_mpris::OVERRUN_SLACK.as_secs()
        );
        println!("     volume         {}", opt(player.volume));
        println!(
            "     loop_status    {}",
            player.loop_status.map_or("<none>".to_owned(), |l| l.as_str().to_owned())
        );
        println!(
            "     shuffle        {}",
            player.shuffle.map_or("<none>".to_owned(), |s| s.to_string())
        );
        println!("     capabilities   {}", capabilities(player));
    }
}

fn capabilities(player: &Player) -> String {
    let caps = player.capabilities;
    [
        ("CanGoNext", caps.go_next),
        ("CanGoPrevious", caps.go_previous),
        ("CanPlay", caps.play),
        ("CanPause", caps.pause),
        ("CanSeek", caps.seek),
        ("CanControl", caps.control),
    ]
    .iter()
    .map(|(name, on)| format!("{name}={on}"))
    .collect::<Vec<_>>()
    .join(" ")
}

fn describe(event: &MprisEvent) -> String {
    match event {
        MprisEvent::PlayerAppeared(bus) => format!("event PlayerAppeared {bus}"),
        MprisEvent::PlayerVanished(bus) => format!("event PlayerVanished {bus}"),
        MprisEvent::StatusChanged { bus_name, status } => {
            format!("event StatusChanged {bus_name} -> {}", status.as_str())
        }
        MprisEvent::TrackChanged { bus_name, metadata } => format!(
            "event TrackChanged {bus_name} -> {:?} by {:?}",
            metadata.title.as_deref().unwrap_or(""),
            metadata.artist()
        ),
        MprisEvent::Seeked {
            bus_name,
            position_us,
        } => format!(
            "event Seeked {bus_name} -> {} ({} us)",
            clock(*position_us),
            position_us
        ),
    }
}

fn opt(value: Option<f64>) -> String {
    value.map_or("<none>".to_owned(), |v| format!("{v:.3}"))
}

fn clock(microseconds: i64) -> String {
    let total = microseconds / 1_000_000;
    format!("{}:{:02}.{:03}", total / 60, total % 60, (microseconds / 1000) % 1000)
}
