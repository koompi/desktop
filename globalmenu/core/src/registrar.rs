// com.canonical.AppMenu.Registrar, served by us. Toolkits do not push menus at a
// panel; they wait for something to own this name and then call RegisterWindow on
// it. With nobody owning it every menubar quietly stays inside its window.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use zbus::blocking::Connection;
use zbus::names::BusName;
use zbus::zvariant::OwnedObjectPath;

pub const BUS_NAME: &str = "com.canonical.AppMenu.Registrar";
pub const OBJECT_PATH: &str = "/com/canonical/AppMenu/Registrar";

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub window_id: u32,
    pub service: String,
    pub path: String,
    pub pid: u32,
    /// Registration order, so a PID match can pick the newest window.
    pub serial: u64,
}

#[derive(Debug, Default)]
pub struct State {
    entries: Vec<Entry>,
    serial: u64,
    /// Exporting the object succeeds even when the name went to somebody else, so this is
    /// the only thing that says our table is the one in use. It gates the mirror and
    /// nothing else: RegisterWindow still answers when false, because an application
    /// registers exactly once and never retries.
    owns_name: bool,
    /// Where the table is mirrored so it survives our own restart.
    runtime_dir: Option<PathBuf>,
}

impl State {
    pub fn new(runtime_dir: Option<PathBuf>) -> Self {
        Self {
            runtime_dir,
            ..Default::default()
        }
    }

    pub fn entries(&self) -> &[Entry] {
        &self.entries
    }

    pub fn owns_name(&self) -> bool {
        self.owns_name
    }

    pub fn set_owns_name(&mut self, owns: bool) {
        self.owns_name = owns;
    }

    pub fn for_window(&self, window_id: u32) -> Option<&Entry> {
        self.entries.iter().find(|e| e.window_id == window_id)
    }

    /// Newest registration owned by `pid`. Used for windows we cannot address
    /// by X11 id; with several windows of one process this is a guess, and the
    /// newest one is the best guess available.
    pub fn for_pid(&self, pid: u32) -> Option<&Entry> {
        self.entries
            .iter()
            .filter(|e| e.pid == pid)
            .max_by_key(|e| e.serial)
    }

    pub fn insert(&mut self, window_id: u32, service: String, path: String, pid: u32) {
        self.drop_window(window_id);
        self.serial += 1;
        self.entries.push(Entry {
            window_id,
            service,
            path,
            pid,
            serial: self.serial,
        });
    }

    /// Forgets every entry for `window_id`, without mirroring the result: callers
    /// that are mid-rebuild persist once at the end instead.
    pub fn drop_window(&mut self, window_id: u32) -> bool {
        let before = self.entries.len();
        self.entries.retain(|e| e.window_id != window_id);
        self.entries.len() != before
    }

    pub fn drop_service(&mut self, service: &str) -> bool {
        let before = self.entries.len();
        self.entries.retain(|e| e.service != service);
        self.entries.len() != before
    }

    fn cache_path(&self) -> Option<PathBuf> {
        self.runtime_dir
            .as_ref()
            .map(|d| d.join("koompi-global-menu.registry"))
    }

    pub fn to_text(&self) -> String {
        let mut out = String::new();
        for e in &self.entries {
            out.push_str(&format!("{}\t{}\t{}\n", e.window_id, e.service, e.path));
        }
        out
    }

    pub fn persist(&self) {
        // The mirror belongs to whoever holds the name. A displaced daemon still
        // receives NameOwnerChanged, and still has a table it built while it was
        // the owner, so without this it would write that stale table over the new
        // owner's mirror and cost it every registration it had recovered.
        if !self.owns_name {
            return;
        }
        let Some(path) = self.cache_path() else { return };
        let tmp = path.with_extension("registry.new");

        // Only a whole file is moved into place. Writing over the mirror directly
        // means a daemon killed mid-write leaves a truncated one behind, and the
        // next daemon recovers whatever survived the truncation.
        if std::fs::write(&tmp, self.to_text()).is_ok() && std::fs::rename(&tmp, &path).is_ok() {
            return;
        }
        let _ = std::fs::remove_file(&tmp);
    }

    pub fn read_mirror(&self) -> Option<String> {
        let path = self.cache_path()?;
        std::fs::read_to_string(path).ok()
    }

    /// Reloads a mirrored table, dropping anything whose application has gone.
    /// Returns the number of entries recovered. The bus queries are injected so
    /// the table logic can be tested without one.
    pub fn restore_from_text(
        &mut self,
        text: &str,
        has_owner: impl Fn(&str) -> bool,
        pid_of: impl Fn(&str) -> u32,
    ) -> usize {
        let mut recovered = 0;
        for line in text.lines() {
            if line.is_empty() {
                continue;
            }
            let mut field = line.split('\t');
            let (Some(id), Some(service), Some(obj_path)) =
                (field.next(), field.next(), field.next())
            else {
                continue;
            };
            let Ok(window_id) = id.parse::<u32>() else {
                continue;
            };
            if !has_owner(service) {
                continue;
            }
            // ALLOW_REPLACEMENT hands the name back when the daemon that took it exits, and
            // each acquisition restores, so appending blindly duplicates what we still hold.
            // The mirror wins: it was written by the owner that displaced us.
            let pid = pid_of(service);
            self.insert(window_id, service.to_owned(), obj_path.to_owned(), pid);
            recovered += 1;
        }
        // Drop the ones that did not survive, so the file does not grow forever.
        self.persist();
        recovered
    }
}

/// True when `service` still has a connection on the bus. An entry whose
/// application has exited must not come back from the mirror.
pub fn has_owner(conn: &Connection, service: &str) -> bool {
    let Ok(name) = BusName::try_from(service) else {
        return false;
    };
    dbus_proxy(conn)
        .ok()
        .and_then(|p| p.name_has_owner(name).ok())
        .unwrap_or(false)
}

pub fn pid_of(conn: &Connection, service: &str) -> u32 {
    let Ok(name) = BusName::try_from(service) else {
        return 0;
    };
    dbus_proxy(conn)
        .ok()
        .and_then(|p| p.get_connection_unix_process_id(name).ok())
        .unwrap_or(0)
}

/// `pid_of` for code that already runs on the connection's executor, where a
/// blocking call would starve the reader that has to deliver its reply.
async fn pid_of_async(conn: &zbus::Connection, service: &str) -> u32 {
    let Ok(name) = BusName::try_from(service) else {
        return 0;
    };
    let Ok(proxy) = zbus::fdo::DBusProxy::new(conn).await else {
        return 0;
    };
    proxy
        .get_connection_unix_process_id(name)
        .await
        .unwrap_or(0)
}

fn dbus_proxy(conn: &Connection) -> zbus::Result<zbus::blocking::fdo::DBusProxy<'_>> {
    zbus::blocking::fdo::DBusProxy::new(conn)
}

/// The change the main loop reacts to: the table moved, so the menu the bar is
/// showing may no longer be the right one.
pub type Notify = std::sync::mpsc::Sender<()>;

pub struct Registrar {
    pub state: Arc<Mutex<State>>,
    pub notify: Notify,
    pub conn: Connection,
}

impl Registrar {
    fn touch(&self) {
        let _ = self.notify.send(());
    }
}

#[zbus::interface(name = "com.canonical.AppMenu.Registrar")]
impl Registrar {
    async fn register_window(
        &mut self,
        window_id: u32,
        menu_object_path: OwnedObjectPath,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) {
        let Some(sender) = header.sender() else { return };
        let service = sender.to_string();
        // Resolved before the lock, and awaited rather than blocked on: this
        // handler runs on the connection's own executor, so a blocking round
        // trip here can never see its reply and sits on the method timeout
        // instead. Qt's QMenuBar constructor waits for RegisterWindow to
        // return, so that timeout was 3 s in front of every Qt window.
        let pid = pid_of_async(self.conn.inner(), &service).await;

        if let Ok(mut state) = self.state.lock() {
            state.insert(window_id, service, menu_object_path.to_string(), pid);
            state.persist();
        }
        self.touch();
    }

    fn unregister_window(&mut self, window_id: u32) {
        if let Ok(mut state) = self.state.lock() {
            if state.drop_window(window_id) {
                state.persist();
            }
        }
        self.touch();
    }

    fn get_menu_for_window(&self, window_id: u32) -> zbus::fdo::Result<(String, OwnedObjectPath)> {
        let state = self
            .state
            .lock()
            .map_err(|_| zbus::fdo::Error::Failed("registry lock poisoned".into()))?;
        let found = state.for_window(window_id).ok_or_else(|| {
            zbus::fdo::Error::Failed("window not registered".into())
        })?;
        let path = OwnedObjectPath::try_from(found.path.as_str())
            .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))?;
        Ok((found.service.clone(), path))
    }

    fn get_menus(&self) -> Vec<(u32, String, OwnedObjectPath)> {
        let Ok(state) = self.state.lock() else {
            return Vec::new();
        };
        state
            .entries()
            .iter()
            .filter_map(|e| {
                OwnedObjectPath::try_from(e.path.as_str())
                    .ok()
                    .map(|p| (e.window_id, e.service.clone(), p))
            })
            .collect()
    }
}

/// Reclaims the previous daemon's table. Applications register exactly once, so
/// without this a daemon restart loses every menu until each app is restarted.
///
/// Every bus query runs before the lock is taken: this is called from the signal
/// thread, and blocking on D-Bus while holding the state lock would race the
/// object server dispatching RegisterWindow.
fn reclaim(conn: &Connection, state: &Arc<Mutex<State>>) -> usize {
    let Some(text) = state.lock().ok().and_then(|s| s.read_mirror()) else {
        return 0;
    };
    let facts: Vec<(String, bool, u32)> = text
        .lines()
        .filter_map(|l| l.split('\t').nth(1))
        .map(|svc| (svc.to_owned(), has_owner(conn, svc), pid_of(conn, svc)))
        .collect();
    let alive = |svc: &str| facts.iter().any(|(s, a, _)| s == svc && *a);
    let pid = |svc: &str| {
        facts
            .iter()
            .find(|(s, _, _)| s == svc)
            .map_or(0, |(_, _, p)| *p)
    };

    let Ok(mut guard) = state.lock() else { return 0 };
    guard.restore_from_text(&text, alive, pid)
}

/// Publishes the registrar and takes the name.
///
/// REPLACE so a respawned daemon takes the name back from a stale owner instead
/// of queueing behind it forever, and ALLOW_REPLACEMENT so the next one can do
/// the same to us. Without both, a daemon restart leaves every application
/// registered with a process that is gone.
pub fn publish(
    conn: &Connection,
    state: Arc<Mutex<State>>,
    notify: Notify,
) -> zbus::Result<()> {
    conn.object_server().at(
        OBJECT_PATH,
        Registrar {
            state: state.clone(),
            notify: notify.clone(),
            conn: conn.clone(),
        },
    )?;

    let flags = zbus::fdo::RequestNameFlags::AllowReplacement
        | zbus::fdo::RequestNameFlags::ReplaceExisting;
    let reply = conn.request_name_with_flags(BUS_NAME, flags)?;
    let acquired = matches!(
        reply,
        zbus::fdo::RequestNameReply::PrimaryOwner | zbus::fdo::RequestNameReply::AlreadyOwner
    );

    if acquired {
        if let Ok(mut guard) = state.lock() {
            guard.set_owns_name(true);
        }
        if reclaim(conn, &state) > 0 {
            eprintln!("global-menu: recovered registrations from the previous daemon");
        }
        let _ = notify.send(());
    }

    let watcher = conn.clone();
    std::thread::spawn(move || {
        let Ok(proxy) = zbus::blocking::fdo::DBusProxy::new(&watcher) else {
            return;
        };
        let Ok(changes) = proxy.receive_name_owner_changed() else {
            return;
        };
        let me = watcher.unique_name().map(|n| n.to_string());
        for signal in changes {
            let Ok(args) = signal.args() else { continue };
            let name = args.name().to_string();
            let new_owner = args.new_owner().as_ref().map(|o| o.to_string());

            if name == BUS_NAME {
                let ours = new_owner.is_some() && new_owner == me;
                if let Ok(mut guard) = state.lock() {
                    guard.set_owns_name(ours);
                }
                if ours {
                    // Owning the name is the point at which our answers start
                    // mattering, so it is where the previous daemon's table is
                    // reclaimed.
                    if reclaim(&watcher, &state) > 0 {
                        eprintln!("global-menu: recovered registrations from the previous daemon");
                    }
                    let _ = notify.send(());
                } else {
                    eprintln!("global-menu: lost {BUS_NAME} to another owner");
                }
                continue;
            }

            if new_owner.is_none() {
                let dropped = state
                    .lock()
                    .map(|mut g| {
                        let d = g.drop_service(&name);
                        if d {
                            g.persist();
                        }
                        d
                    })
                    .unwrap_or(false);
                if dropped {
                    let _ = notify.send(());
                }
            }
        }
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state() -> State {
        State::new(None)
    }

    #[test]
    fn for_pid_picks_the_newest_window_of_that_process() {
        let mut s = state();
        s.insert(1, ":1.5".into(), "/a".into(), 42);
        s.insert(2, ":1.5".into(), "/b".into(), 42);
        s.insert(3, ":1.9".into(), "/c".into(), 43);

        assert_eq!(s.for_pid(42).unwrap().window_id, 2);
        assert_eq!(s.for_pid(43).unwrap().window_id, 3);
        assert!(s.for_pid(99).is_none());
    }

    #[test]
    fn registering_the_same_window_replaces_rather_than_duplicates() {
        let mut s = state();
        s.insert(7, ":1.5".into(), "/old".into(), 42);
        s.insert(7, ":1.6".into(), "/new".into(), 43);

        assert_eq!(s.entries().len(), 1);
        assert_eq!(s.for_window(7).unwrap().path, "/new");
    }

    #[test]
    fn drop_service_forgets_every_window_of_that_connection() {
        let mut s = state();
        s.insert(1, ":1.5".into(), "/a".into(), 42);
        s.insert(2, ":1.5".into(), "/b".into(), 42);
        s.insert(3, ":1.9".into(), "/c".into(), 43);

        assert!(s.drop_service(":1.5"));
        assert_eq!(s.entries().len(), 1);
        assert!(!s.drop_service(":1.5"));
    }

    #[test]
    fn mirror_round_trips() {
        let mut s = state();
        s.insert(4243, ":1.5".into(), "/MenuBar".into(), 42);
        s.insert(4244, ":1.6".into(), "/MenuBar".into(), 43);

        let text = s.to_text();
        let mut restored = state();
        let n = restored.restore_from_text(&text, |_| true, |_| 0);

        assert_eq!(n, 2);
        assert_eq!(restored.entries().len(), 2);
        assert_eq!(restored.for_window(4243).unwrap().service, ":1.5");
    }

    // The bus check inside restore is what stops a dead application coming back
    // from the mirror; the e2e suite asserts this at the process level.
    #[test]
    fn restore_drops_entries_whose_application_has_exited() {
        let mut s = state();
        let text = "1\t:1.5\t/MenuBar\n2\t:1.6\t/MenuBar\n";

        let n = s.restore_from_text(text, |svc| svc == ":1.6", |_| 0);

        assert_eq!(n, 1);
        assert_eq!(s.entries().len(), 1);
        assert_eq!(s.entries()[0].service, ":1.6");
    }

    #[test]
    fn restore_does_not_duplicate_what_is_already_held() {
        let mut s = state();
        s.insert(4245, ":1.5".into(), "/MenuBar".into(), 42);
        let text = s.to_text();

        let n = s.restore_from_text(&text, |_| true, |_| 42);

        assert_eq!(n, 1);
        assert_eq!(s.entries().len(), 1);
    }

    #[test]
    fn a_malformed_mirror_line_is_skipped_not_fatal() {
        let mut s = state();
        let text = "notanumber\t:1.5\t/M\n\n5\t:1.6\n6\t:1.7\t/OK\n";

        let n = s.restore_from_text(text, |_| true, |_| 0);

        assert_eq!(n, 1);
        assert_eq!(s.entries()[0].window_id, 6);
    }

    #[test]
    fn a_displaced_daemon_does_not_write_the_mirror() {
        let dir = std::env::temp_dir().join(format!("gm-test-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let mut s = State::new(Some(dir.clone()));
        s.insert(1, ":1.5".into(), "/a".into(), 42);

        s.set_owns_name(false);
        s.persist();
        assert!(s.read_mirror().is_none(), "a daemon without the name wrote the mirror");

        s.set_owns_name(true);
        s.persist();
        assert!(s.read_mirror().is_some());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
