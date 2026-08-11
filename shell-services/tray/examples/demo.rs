//! Host mode against whatever watcher this seat already has. Nothing here takes a name and
//! nothing here activates an item.
//!
//! ```text
//! demo                       list the tray, then follow it
//! demo menu <id|key>         dump one item's whole menu tree
//! demo capture <id|key> <f>  write that item's raw GetLayout reply to a file
//! ```

use std::time::Instant;

use koompi_service::Service;
use koompi_tray::{MenuItem, Pixmap, ToggleType, TrayConfig, TrayEvent, TrayItem, TrayService};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let service = TrayService::connect(TrayConfig::default()).await?;

    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        [] => follow(service).await,
        ["menu", wanted] => dump_menu(&service, wanted).await,
        ["capture", wanted, path] => capture(&service, wanted, path).await,
        _ => {
            eprintln!("usage: demo [menu <id|key>] [capture <id|key> <file>]");
            std::process::exit(2);
        }
    }
}

async fn follow(service: TrayService) -> Result<(), Box<dyn std::error::Error>> {
    let state = service.state();
    println!(
        "watcher {}, {} item(s)",
        if state.watcher_present {
            "present"
        } else {
            "absent"
        },
        state.items.len()
    );
    for item in &state.items {
        print_item(item);
    }

    println!("\n-- following, ^C to stop --");
    let started = Instant::now();
    let mut changes = service.subscribe();
    let mut events = service.events();

    loop {
        tokio::select! {
            changed = changes.changed() => {
                if changed.is_err() {
                    return Ok(());
                }
                let state = changes.borrow_and_update().clone();
                let summary: Vec<String> = state
                    .items
                    .iter()
                    .map(|item| format!("{} [{}]", item.id, item.status.as_str()))
                    .collect();
                println!(
                    "[{:>6.1}s] state watcher={} items={}",
                    started.elapsed().as_secs_f64(),
                    state.watcher_present,
                    if summary.is_empty() {
                        "<none>".to_owned()
                    } else {
                        summary.join(", ")
                    }
                );
            }
            event = events.recv() => {
                match event {
                    Ok(event) => println!(
                        "[{:>6.1}s] event {}",
                        started.elapsed().as_secs_f64(),
                        describe(&event)
                    ),
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => return Ok(()),
                    Err(lagged) => println!("[events] {lagged}"),
                }
            }
        }
    }
}

fn describe(event: &TrayEvent) -> String {
    match event {
        TrayEvent::ItemRegistered(key) => format!("registered   {key}"),
        TrayEvent::ItemUnregistered(key) => format!("unregistered {key}"),
        TrayEvent::MenuActivationRequested { item, id, timestamp } => {
            format!("menu activation requested by {item}: id={id} t={timestamp}")
        }
        TrayEvent::MenuLayoutUpdated {
            item,
            revision,
            parent,
        } => format!("menu layout updated on {item}: revision={revision} parent={parent}"),
    }
}

fn print_item(item: &TrayItem) {
    println!("\n{}", item.key());
    println!("  id               {}", item.id);
    println!("  title            {}", item.title);
    println!("  category         {}", item.category.as_str());
    println!("  status           {}", item.status.as_str());
    println!("  icon_name        {}", show(&item.icon_name));
    println!("  icon_pixmap      {}", pixmaps(&item.icon_pixmap));
    println!("  icon_theme_path  {}", show(&item.icon_theme_path));
    println!("  attention_icon   {}", show(&item.attention_icon_name));
    println!(
        "  attention_pixmap {}",
        pixmaps(&item.attention_icon_pixmap)
    );
    println!("  overlay_icon     {}", show(&item.overlay_icon_name));
    println!("  overlay_pixmap   {}", pixmaps(&item.overlay_icon_pixmap));
    match &item.tooltip {
        Some(tooltip) => println!(
            "  tooltip          icon={} title={:?} description={:?}",
            show(&tooltip.icon_name),
            tooltip.title,
            tooltip.description
        ),
        None => println!("  tooltip          <none>"),
    }
    println!("  item_is_menu     {}", item.item_is_menu);
    println!("  menu             {}", item.menu.as_deref().unwrap_or("<none>"));
    println!("  window_id        {}", item.window_id);
    println!("  owner            {}", item.owner);
}

fn show(value: &str) -> &str {
    if value.is_empty() {
        "<empty>"
    } else {
        value
    }
}

/// Dimensions and a byte count. The bytes themselves stay raw and undecoded, which is the
/// whole of this crate's icon policy.
fn pixmaps(pixmaps: &[Pixmap]) -> String {
    if pixmaps.is_empty() {
        return "<none>".to_owned();
    }
    pixmaps
        .iter()
        .map(|p| format!("{}x{} ({} bytes ARGB32)", p.width, p.height, p.argb32.len()))
        .collect::<Vec<_>>()
        .join(", ")
}

fn find(service: &TrayService, wanted: &str) -> Result<String, String> {
    let state = service.state();
    state
        .items
        .iter()
        .find(|item| item.id == wanted || item.key() == wanted)
        .map(TrayItem::key)
        .ok_or_else(|| {
            let known: Vec<String> = state.items.iter().map(|item| item.id.clone()).collect();
            format!("no tray item {wanted:?}; this seat has {known:?}")
        })
}

async fn dump_menu(
    service: &TrayService,
    wanted: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let key = find(service, wanted)?;
    let item = service.item(&key).expect("just found it");
    println!(
        "{} menu at {} ({})",
        item.id,
        item.menu.as_deref().unwrap_or("<none>"),
        item.address.service
    );
    print_menu(&service.menu(&key).await?, 0);
    Ok(())
}

fn print_menu(item: &MenuItem, depth: usize) {
    let indent = "  ".repeat(depth);
    let mut notes = Vec::new();
    if item.separator {
        notes.push("separator".to_owned());
    }
    if !item.enabled {
        notes.push("disabled".to_owned());
    }
    if !item.visible {
        notes.push("hidden".to_owned());
    }
    if item.toggle_type != ToggleType::None {
        notes.push(format!("{:?}={:?}", item.toggle_type, item.toggle_state));
    }
    if item.has_submenu {
        notes.push("submenu".to_owned());
    }
    if !item.icon_name.is_empty() {
        notes.push(format!("icon={}", item.icon_name));
    }

    println!(
        "{indent}[{}] {}{}",
        item.id,
        if item.label.is_empty() {
            "-".to_owned()
        } else {
            item.label.clone()
        },
        if notes.is_empty() {
            String::new()
        } else {
            format!("  ({})", notes.join(", "))
        }
    );
    for child in &item.children {
        print_menu(child, depth + 1);
    }
}

/// Writes the `GetLayout` reply body untouched, which is where the decode test's fixture
/// came from. It goes around the crate on purpose: what is wanted is the application's
/// bytes, before anything here has looked at them.
async fn capture(
    service: &TrayService,
    wanted: &str,
    path: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let key = find(service, wanted)?;
    let item = service.item(&key).expect("just found it");
    let menu = item.menu.clone().ok_or("that item has no menu")?;

    let conn = zbus::Connection::session().await?;
    let reply = conn
        .call_method(
            Some(item.address.service.as_str()),
            menu.as_str(),
            Some("com.canonical.dbusmenu"),
            "GetLayout",
            &(
                0i32,
                -1i32,
                &[
                    "label",
                    "enabled",
                    "visible",
                    "type",
                    "children-display",
                    "toggle-type",
                    "toggle-state",
                    "icon-name",
                ][..],
            ),
        )
        .await?;

    let body = reply.body();
    let bytes = body.data().bytes();
    std::fs::write(path, bytes)?;
    println!(
        "wrote {} bytes of {} signature {} to {path}",
        bytes.len(),
        item.id,
        body.signature()
    );
    Ok(())
}
