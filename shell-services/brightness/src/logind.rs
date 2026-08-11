use zbus::proxy;

/// `session/auto` resolves to the caller's own session, so nothing here has to look up
/// `XDG_SESSION_ID` or hold a `koompi-session` dependency to find it.
#[proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1/session/auto"
)]
pub trait Session {
    /// The write `/sys/class/backlight/*/brightness` refuses without root. logind is
    /// root, checks that the caller owns an active session on the seat, and writes it.
    fn set_brightness(&self, subsystem: &str, name: &str, brightness: u32) -> zbus::Result<()>;
}
