//! Connect, print the state this session is actually in, then follow it.
//!
//! `cargo run -p koompi-hyprland --example demo`

use koompi_hyprland::{categories_of, HyprlandService, HyprlandState};
use koompi_service::{PollRate, Service};

#[tokio::main]
async fn main() -> koompi_service::Result<()> {
    let hyprland = HyprlandService::start(PollRate::NORMAL).await?;
    println!("instance dir  {}", hyprland.ipc().instance_dir().display());
    println!("debounce      {:?}", hyprland.debounce());

    let mut state = hyprland.ready().await;
    print_initial(&state);

    let mut events = hyprland.events();
    let mut states = hyprland.subscribe();
    println!("\nfollowing. switch workspace or open a window.\n");

    loop {
        tokio::select! {
            event = events.recv() => match event {
                Ok(event) => println!("event    {}>>{}", event.name, event.data),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    println!("event    (dropped {n} while behind)");
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return Ok(()),
            },
            changed = states.changed() => {
                if changed.is_err() {
                    return Ok(());
                }
                let next = states.borrow_and_update().clone();
                print_change(&state, &next);
                state = next;
            }
        }
    }
}

fn print_initial(state: &HyprlandState) {
    println!("connected     {}", state.connected);

    println!("\nmonitors      {}", state.monitors.len());
    for monitor in &state.monitors {
        println!(
            "  {} {}x{}@{:.2} scale {} focused {} workspace {}",
            monitor.name,
            monitor.width,
            monitor.height,
            monitor.refresh_rate,
            monitor.scale,
            monitor.focused,
            monitor.active_workspace.name,
        );
    }

    println!("\nworkspaces    {}", state.workspaces.len());
    for workspace in &state.workspaces {
        println!(
            "  id {:>4} name {:<10} monitor {:<8} windows {}",
            workspace.id, workspace.name, workspace.monitor, workspace.windows,
        );
    }
    println!(
        "  active      {}",
        state
            .active_workspace
            .as_ref()
            .map(|w| format!("id {} name {}", w.id, w.name))
            .unwrap_or_else(|| "none".into())
    );

    println!("\nwindows       {}", state.windows.len());
    for window in &state.windows {
        println!(
            "  {} ws {:>4} {:<28} {}",
            window.address,
            window.workspace.id,
            window.class,
            truncate(&window.title, 50),
        );
    }
    println!("  active      {}", describe_window(state));

    println!("\nlayers");
    for (monitor, layers) in &state.layers {
        for (level, surfaces) in &layers.levels {
            for surface in surfaces {
                println!(
                    "  {monitor} level {level} {:<26} {}x{}",
                    surface.namespace, surface.w, surface.h
                );
            }
        }
    }

    println!("\nkeybinds      {}", state.keybinds.len());
    for bind in state.keybinds.iter().take(3) {
        println!(
            "  modmask {:<4} {:<12} {}",
            bind.modmask, bind.key, bind.description
        );
    }
    println!("  categories  {}", categories_of(&state.keybinds).join(", "));

    println!("\nkeyboard      {}", state.keyboard.name);
    println!("  layouts     {}", state.keyboard.layout_codes.join(","));
    println!(
        "  active      {} ({})",
        state.keyboard.active_name, state.keyboard.active_code
    );
    println!("  submap      {:?}", state.submap);
}

fn print_change(before: &HyprlandState, after: &HyprlandState) {
    if before.connected != after.connected {
        println!(
            "  state    connected {} -> {}",
            before.connected, after.connected
        );
    }
    if before.active_workspace != after.active_workspace {
        println!(
            "  state    active workspace {} -> {}",
            before
                .active_workspace
                .as_ref()
                .map_or("none".into(), |w| w.name.clone()),
            after
                .active_workspace
                .as_ref()
                .map_or("none".into(), |w| w.name.clone()),
        );
    }
    if before.active_window != after.active_window {
        println!(
            "  state    active window {} -> {}",
            describe_window(before),
            describe_window(after)
        );
    }
    if before.windows != after.windows {
        println!(
            "  state    windows {} -> {} [{}]",
            before.windows.len(),
            after.windows.len(),
            after
                .windows
                .iter()
                .map(|w| format!("{}:ws{}", w.class, w.workspace.id))
                .collect::<Vec<_>>()
                .join(" ")
        );
    }
    if before.workspaces != after.workspaces {
        println!(
            "  state    workspaces [{}]",
            after
                .workspaces
                .iter()
                .map(|w| format!("{}:{}win", w.name, w.windows))
                .collect::<Vec<_>>()
                .join(" ")
        );
    }
    if before.monitors != after.monitors {
        println!("  state    monitors {}", after.monitors.len());
    }
    if before.layers != after.layers {
        let count: usize = after
            .layers
            .values()
            .flat_map(|m| m.levels.values())
            .map(Vec::len)
            .sum();
        println!("  state    layer surfaces {count}");
    }
    if before.keybinds != after.keybinds {
        println!("  state    keybinds {}", after.keybinds.len());
    }
    if before.keyboard != after.keyboard {
        println!(
            "  state    layout {} ({})",
            after.keyboard.active_name, after.keyboard.active_code
        );
    }
    if before.submap != after.submap {
        println!("  state    submap {:?}", after.submap);
    }
}

fn describe_window(state: &HyprlandState) -> String {
    state
        .active_window
        .as_ref()
        .map(|w| format!("{} ws{} {}", w.class, w.workspace.id, truncate(&w.title, 40)))
        .unwrap_or_else(|| "none".into())
}

fn truncate(text: &str, limit: usize) -> String {
    match text.char_indices().nth(limit) {
        Some((cut, _)) => format!("{}...", &text[..cut]),
        None => text.to_string(),
    }
}
