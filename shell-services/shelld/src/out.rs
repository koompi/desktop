//! One task owns stdout, so a line written from a service task can never interleave with
//! a reply written from the command loop.

use serde_json::Value;
use tokio::io::{AsyncWriteExt, BufWriter};
use tokio::sync::{mpsc, oneshot};

enum Item {
    Line(String),
    Drain(oneshot::Sender<()>),
}

#[derive(Clone)]
pub struct Out(mpsc::UnboundedSender<Item>);

impl Out {
    pub fn stdout() -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        tokio::spawn(pump(rx));
        Self(tx)
    }

    pub fn send(&self, message: Value) {
        let _ = self.0.send(Item::Line(message.to_string()));
    }

    /// Returns once everything queued ahead of it has reached the terminal. `quit` owes a
    /// reply before the process goes away, and exiting on the send alone loses it.
    pub async fn drain(&self) {
        let (tx, rx) = oneshot::channel();
        if self.0.send(Item::Drain(tx)).is_ok() {
            let _ = rx.await;
        }
    }
}

async fn pump(mut rx: mpsc::UnboundedReceiver<Item>) {
    let mut stdout = BufWriter::new(tokio::io::stdout());
    while let Some(item) = rx.recv().await {
        match item {
            Item::Line(line) => {
                // flushed per line: a consumer reading with SplitParser sees nothing until
                // the newline reaches it, and there is no second writer to piggyback on
                if stdout.write_all(line.as_bytes()).await.is_err()
                    || stdout.write_all(b"\n").await.is_err()
                    || stdout.flush().await.is_err()
                {
                    return;
                }
            }
            Item::Drain(done) => {
                let _ = done.send(());
            }
        }
    }
}
