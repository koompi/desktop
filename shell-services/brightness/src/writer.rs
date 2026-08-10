//! The debounce, and the reason for it.
//!
//! `Brightness.qml:148-153` waits 300 ms before a DDC write and nothing before an
//! internal one, because a DDC round trip is slow and misbehaves under rapid change.
//! The comment at `:120-122` puts the internal delay at 0 only because a
//! `brightnessctl` fork per animation frame was not worth the smoothness; a logind
//! method call is cheap enough that it stays 0 for a better reason than that.

use std::future::Future;
use std::time::Duration;

use tokio::sync::watch;

pub const DDC_DEBOUNCE: Duration = Duration::from_millis(300);
pub const LOGIND_DEBOUNCE: Duration = Duration::ZERO;

/// Every value that arrives inside the window collapses into one write of the last of
/// them: the channel keeps only the newest, so the sleep is the whole mechanism.
pub async fn run<F, Fut>(mut rx: watch::Receiver<u32>, debounce: Duration, mut write: F)
where
    F: FnMut(u32) -> Fut,
    Fut: Future<Output = ()>,
{
    while rx.changed().await.is_ok() {
        if !debounce.is_zero() {
            tokio::time::sleep(debounce).await;
        }
        let value = *rx.borrow_and_update();
        write(value).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    fn recorder() -> (
        Arc<Mutex<Vec<u32>>>,
        impl FnMut(u32) -> std::future::Ready<()>,
    ) {
        let written = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&written);
        (written, move |value| {
            sink.lock().unwrap().push(value);
            std::future::ready(())
        })
    }

    /// Real time rather than a paused clock: `tokio`'s `test-util` feature is not one
    /// the workspace declares, and turning it on here would turn it on for every other
    /// crate in the build.
    #[tokio::test]
    async fn a_burst_inside_the_ddc_window_is_one_write_of_the_last_value() {
        let (tx, rx) = watch::channel(0);
        let (written, write) = recorder();
        tokio::spawn(run(rx, DDC_DEBOUNCE, write));

        for value in [10, 20, 30, 40, 50] {
            tx.send(value).unwrap();
            tokio::task::yield_now().await;
        }
        tokio::time::sleep(DDC_DEBOUNCE * 2).await;

        assert_eq!(*written.lock().unwrap(), vec![50]);
    }

    #[tokio::test]
    async fn a_second_burst_after_the_window_is_a_second_write() {
        let (tx, rx) = watch::channel(0);
        let (written, write) = recorder();
        tokio::spawn(run(rx, DDC_DEBOUNCE, write));

        tx.send(10).unwrap();
        tokio::time::sleep(DDC_DEBOUNCE * 2).await;
        tx.send(20).unwrap();
        tokio::time::sleep(DDC_DEBOUNCE * 2).await;

        assert_eq!(*written.lock().unwrap(), vec![10, 20]);
    }

    /// The internal panel has no window at all, which is the difference worth keeping:
    /// a gap far shorter than the DDC one still produces a write each.
    #[tokio::test]
    async fn the_logind_path_writes_each_value_with_no_window() {
        let (tx, rx) = watch::channel(0);
        let (written, write) = recorder();
        tokio::spawn(run(rx, LOGIND_DEBOUNCE, write));

        for value in [10, 20, 30] {
            tx.send(value).unwrap();
            tokio::time::sleep(Duration::from_millis(20)).await;
        }

        assert_eq!(*written.lock().unwrap(), vec![10, 20, 30]);
    }

    #[test]
    fn the_two_backends_keep_the_two_delays_the_qml_had() {
        assert_eq!(DDC_DEBOUNCE, Duration::from_millis(300));
        assert_eq!(LOGIND_DEBOUNCE, Duration::ZERO);
    }
}
