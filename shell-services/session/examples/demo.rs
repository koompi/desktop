//! Reads this seat and then follows it.
//!
//! Nothing here takes an action and there is no flag that takes one: every method on
//! `org.freedesktop.login1` can end the session or power the machine off, and this
//! binary is run against a seat somebody is logged into.

use koompi_service::Service;
use koompi_session::{SessionConfig, SessionService, SessionState};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let service = SessionService::connect(SessionConfig::default()).await?;

    print_state(&service.state());
    print_inhibitors(&service).await;
    print_action_calls(&service);

    println!("\n-- following signals, ^C to stop --");
    let mut events = service.events();
    let mut states = service.subscribe();
    loop {
        tokio::select! {
            event = events.recv() => match event {
                Ok(event) => println!("event  {event:?}"),
                Err(_) => break,
            },
            changed = states.changed() => {
                if changed.is_err() {
                    break;
                }
                let state = states.borrow_and_update().clone();
                println!(
                    "state  active={} locked_hint={} idle_hint={} state={} suspend={} block_inhibited={}",
                    state.session.active,
                    state.session.locked_hint,
                    state.session.idle_hint,
                    state.session.state,
                    state.capabilities.suspend.as_str(),
                    state.block_inhibited,
                );
            }
        }
    }
    Ok(())
}

fn print_state(state: &SessionState) {
    let session = &state.session;
    println!("session");
    println!("  id               {}", session.id);
    println!("  path             {}", session.path);
    println!("  user             {} ({})", session.name, session.uid);
    println!("  class            {}", session.class);
    println!("  type             {}", session.kind);
    println!("  state            {}", session.state);
    println!("  active           {}", session.active);
    println!("  locked_hint      {}", session.locked_hint);
    println!("  idle_hint        {}", session.idle_hint);
    println!("  can_lock         {}", session.can_lock);
    println!("  can_idle         {}", session.can_idle);
    println!("  desktop          {}", session.desktop);
    println!("  tty              {} (vt {})", session.tty, session.vt);
    println!("  remote           {}", session.remote);
    println!("  service          {}", session.service);
    println!("  scope            {}", session.scope);
    println!(
        "  leader           {}{}",
        session.leader,
        if session.leader_is_display_manager_helper() {
            "  <- display manager helper, see 3d2957e5"
        } else {
            ""
        }
    );
    println!(
        "  seat             {}",
        session.seat.as_deref().unwrap_or("<none>")
    );

    match &state.seat {
        Some(seat) => {
            println!("\nseat {}", seat.id);
            println!("  path             {}", seat.path);
            println!("  can_graphical    {}", seat.can_graphical);
            println!("  can_tty          {}", seat.can_tty);
            println!("  idle_hint        {}", seat.idle_hint);
            println!(
                "  active_session   {}",
                seat.active_session.as_deref().unwrap_or("<none>")
            );
            println!("  sessions         {}", seat.sessions.join(", "));
        }
        None => println!("\nthis session has no seat"),
    }

    println!(
        "\ncapabilities  (reply / supported / offered-by-the-qml-grep / inhibited / permitted)"
    );
    for (action, capability) in state.capabilities.iter() {
        println!(
            "  {:<24} {:<28} supported={:<5} offered={:<5} inhibited={:<5} permitted={}",
            action.can_member(),
            capability.as_str(),
            capability.supported(),
            capability.offered(),
            capability.inhibited(),
            capability.permitted(),
        );
    }

    println!("\nmanager");
    println!("  preparing_for_sleep     {}", state.preparing_for_sleep);
    println!("  preparing_for_shutdown  {}", state.preparing_for_shutdown);
    println!("  block_inhibited         {}", state.block_inhibited);
    println!("  delay_inhibited         {}", state.delay_inhibited);
    println!("  poll_rate               x{}", state.poll_rate.factor());
}

async fn print_inhibitors(service: &SessionService) {
    println!("\nactive inhibitors  (what systemd-inhibit --list prints)");
    match service.list_inhibitors().await {
        Ok(inhibitors) => {
            for inhibitor in inhibitors {
                println!(
                    "  {:<14} uid={:<6} pid={:<8} {:<6} {:<30} {}",
                    inhibitor.who,
                    inhibitor.uid,
                    inhibitor.pid,
                    inhibitor.mode.map_or("?", |mode| mode.as_wire()),
                    inhibitor.what.to_string(),
                    inhibitor.why,
                );
            }
        }
        Err(error) => println!("  {error}"),
    }
}

/// The nine calls, built and printed. None is sent: `Call::send` is not reached from
/// this binary at all.
fn print_action_calls(service: &SessionService) {
    use koompi_session::{PowerAction, SessionAction};

    println!("\nactions, built and not sent");
    let calls = PowerAction::ALL
        .into_iter()
        .map(|action| service.power_call(action, true))
        .chain(
            [
                SessionAction::Lock,
                SessionAction::Unlock,
                SessionAction::Terminate,
            ]
            .into_iter()
            .map(|action| service.session_call(action)),
        );
    for call in calls {
        println!(
            "  {} {} {}{}",
            call.path,
            call.interface,
            call.member,
            if call.strands_the_seat() {
                "   <- ends this session; koompi-logout owns the ordering"
            } else {
                ""
            }
        );
    }
}
