// Resolves the menu the focused application exports, over whichever protocol it
// speaks, and turns a click in the bar back into a call on that application.
//
// This is the half otto links directly. The stdio wire protocol lives in the
// daemon crate; nothing here knows the shell exists.

pub mod compositor;
pub mod dbusmenu;
pub mod gtkmenu;
pub mod menu;
pub mod registrar;
pub mod x11;

pub use compositor::{ActiveWindow, FocusSource};
pub use menu::{Item, Table, Target};

/// Build the session connection through this, never `Connection::session()`.
/// zbus has no per-call timeout, so this is the only thing standing between an
/// application that never answers and a wedged daemon. Both readers rely on it.
pub fn connect() -> zbus::Result<zbus::blocking::Connection> {
    zbus::blocking::connection::Builder::session()?
        .method_timeout(std::time::Duration::from_millis(3000))
        .build()
}
