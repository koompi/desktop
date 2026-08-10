//! A compositor that goes away and comes back, answering with this machine's own captured
//! payloads. The live version of this is in the J02 report; this is the one that runs in
//! CI, where there is no Hyprland at all.

use std::path::{Path, PathBuf};
use std::time::Duration;

use koompi_hyprland::{HyprlandService, Ipc};
use koompi_service::{PollRate, Service};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tokio::task::JoinHandle;

fn reply_for(command: &str) -> &'static str {
    match command {
        "j/clients" => include_str!("fixtures/clients.json"),
        "j/workspaces" => include_str!("fixtures/workspaces.json"),
        "j/activeworkspace" => include_str!("fixtures/activeworkspace.json"),
        "j/activewindow" => include_str!("fixtures/activewindow.json"),
        "j/monitors" => include_str!("fixtures/monitors.json"),
        "j/layers" => include_str!("fixtures/layers.json"),
        "j/devices" => include_str!("fixtures/devices.json"),
        "binds" => include_str!("fixtures/binds.txt"),
        _ => "",
    }
}

fn spawn_stub(dir: &Path) -> JoinHandle<()> {
    let _ = std::fs::remove_file(dir.join(".socket.sock"));
    let _ = std::fs::remove_file(dir.join(".socket2.sock"));
    let commands = UnixListener::bind(dir.join(".socket.sock")).unwrap();
    let events = UnixListener::bind(dir.join(".socket2.sock")).unwrap();

    tokio::spawn(async move {
        let answer = async move {
            loop {
                let Ok((mut stream, _)) = commands.accept().await else {
                    return;
                };
                tokio::spawn(async move {
                    let mut command = String::new();
                    let _ = stream.read_to_string(&mut command).await;
                    let _ = stream.write_all(reply_for(command.trim()).as_bytes()).await;
                    let _ = stream.shutdown().await;
                });
            }
        };
        let stream_events = async move {
            loop {
                let Ok((mut stream, _)) = events.accept().await else {
                    return;
                };
                tokio::spawn(async move {
                    let _ = stream.write_all(b"workspacev2>>1,1\n").await;
                    std::future::pending::<()>().await;
                });
            }
        };
        tokio::join!(answer, stream_events);
    })
}

async fn wait_connected(service: &HyprlandService, want: bool) -> bool {
    let mut rx = service.subscribe();
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if rx.borrow_and_update().connected == want {
                return;
            }
            if rx.changed().await.is_err() {
                return;
            }
        }
    })
    .await
    .is_ok()
}

fn scratch_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("koompi-hyprland-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[tokio::test]
async fn the_service_reconnects_after_the_socket_goes_away() {
    let dir = scratch_dir("reconnect");
    let stub = spawn_stub(&dir);

    let service = HyprlandService::with_ipc(Ipc::new(&dir), PollRate::NORMAL);
    assert!(wait_connected(&service, true).await, "never connected");

    let state = service.state();
    assert_eq!(state.windows.len(), 5);
    assert_eq!(state.monitors.len(), 1);
    assert_eq!(state.keybinds.len(), 10);
    assert_eq!(state.keyboard.layout_codes, ["us", "kh"]);
    assert_eq!(state.active_workspace.as_ref().unwrap().id, 1);

    stub.abort();
    std::fs::remove_file(dir.join(".socket.sock")).unwrap();
    std::fs::remove_file(dir.join(".socket2.sock")).unwrap();
    assert!(
        wait_connected(&service, false).await,
        "the outage went unnoticed"
    );

    let _stub = spawn_stub(&dir);
    assert!(
        wait_connected(&service, true).await,
        "did not come back after the socket returned"
    );
    assert_eq!(service.state().windows.len(), 5);

    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn an_instance_that_never_answers_leaves_the_state_empty_rather_than_panicking() {
    let dir = scratch_dir("dead");
    let service = HyprlandService::with_ipc(Ipc::new(&dir), PollRate::NORMAL);

    tokio::time::sleep(Duration::from_millis(300)).await;

    let state = service.state();
    assert!(!state.connected);
    assert!(state.windows.is_empty());

    std::fs::remove_dir_all(&dir).ok();
}
