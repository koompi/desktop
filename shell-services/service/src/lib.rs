//! The shape every KOOMPI shell service presents, and nothing else.
//!
//! State travels over [`tokio::sync::watch`]: last value wins, so a consumer that fell
//! behind sees what is true now rather than a queue of states that are already wrong.
//! Events travel over [`tokio::sync::broadcast`], reserved for what must not be dropped,
//! which in this campaign means notifications and tray menu activations.
//!
//! No crate here may depend on a toolkit, a windowing library or a drawing crate.

use std::time::Duration;

/// A source of state that a consumer can read now or follow.
///
/// Commands stay as inherent async methods on the concrete service. Muting an audio sink
/// and hibernating a seat have nothing in common but the word "command".
pub trait Service {
    type State: Clone + Send + Sync + 'static;

    fn state(&self) -> Self::State;

    fn subscribe(&self) -> tokio::sync::watch::Receiver<Self::State>;
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("d-bus: {0}")]
    Bus(#[from] zbus::Error),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("protocol: {0}")]
    Protocol(String),

    /// The backing daemon is absent, not broken. A seat with no battery, no bluetooth
    /// adapter and no NetworkManager is a working seat, and a consumer has to be able to
    /// draw that differently from a service that failed.
    #[error("{0} is not available")]
    Unavailable(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// Capped exponential delay for reconnecting to a bus name or a socket that went away.
#[derive(Debug, Clone)]
pub struct Backoff {
    base: Duration,
    cap: Duration,
    next: Duration,
}

impl Backoff {
    pub fn new(base: Duration, cap: Duration) -> Self {
        let base = base.min(cap);
        Self { base, cap, next: base }
    }

    /// The delay to wait before the next attempt, doubling until it reaches the cap.
    pub fn next_delay(&mut self) -> Duration {
        let delay = self.next;
        self.next = self.next.checked_mul(2).unwrap_or(self.cap).min(self.cap);
        delay
    }

    pub async fn wait(&mut self) {
        tokio::time::sleep(self.next_delay()).await;
    }

    /// Call once a connection is up again, so the next outage starts short.
    pub fn reset(&mut self) {
        self.next = self.base;
    }
}

impl Default for Backoff {
    fn default() -> Self {
        Self::new(Duration::from_millis(250), Duration::from_secs(30))
    }
}

/// The shell-wide poll multiplier, `PowerSaving.qml:33` today: one factor for every
/// service rather than a knob per service.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PollRate {
    factor: u32,
}

impl PollRate {
    pub const NORMAL: Self = Self { factor: 1 };
    pub const SAVING: Self = Self { factor: 2 };

    pub fn new(factor: u32) -> Self {
        Self {
            factor: factor.max(1),
        }
    }

    pub fn factor(&self) -> u32 {
        self.factor
    }

    pub fn interval(&self, base: Duration) -> Duration {
        base.saturating_mul(self.factor)
    }
}

impl Default for PollRate {
    fn default() -> Self {
        Self::NORMAL
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::watch;

    struct Counter {
        tx: watch::Sender<u32>,
    }

    impl Service for Counter {
        type State = u32;

        fn state(&self) -> u32 {
            *self.tx.borrow()
        }

        fn subscribe(&self) -> watch::Receiver<u32> {
            self.tx.subscribe()
        }
    }

    #[tokio::test]
    async fn watch_subscriber_observes_a_change_made_after_subscribing() {
        let service = Counter {
            tx: watch::channel(0).0,
        };
        let mut rx = service.subscribe();
        assert_eq!(*rx.borrow(), 0);

        service.tx.send(7).unwrap();

        rx.changed().await.unwrap();
        assert_eq!(*rx.borrow(), 7);
        assert_eq!(service.state(), 7);
    }

    #[test]
    fn backoff_stops_growing_at_its_cap() {
        let cap = Duration::from_millis(800);
        let mut backoff = Backoff::new(Duration::from_millis(100), cap);

        let delays: Vec<Duration> = (0..8).map(|_| backoff.next_delay()).collect();

        assert_eq!(
            delays,
            [100, 200, 400, 800, 800, 800, 800, 800].map(Duration::from_millis)
        );

        backoff.reset();
        assert_eq!(backoff.next_delay(), Duration::from_millis(100));
    }

    #[test]
    fn poll_rate_scales_the_base_interval() {
        let base = Duration::from_secs(5);
        assert_eq!(PollRate::default().interval(base), base);
        assert_eq!(PollRate::SAVING.interval(base), Duration::from_secs(10));
        assert_eq!(PollRate::new(0), PollRate::NORMAL);
    }
}
