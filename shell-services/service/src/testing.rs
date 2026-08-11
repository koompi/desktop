//! A peer on a socket pair, for the tests that prove a service keeps reading its bus
//! while it is busy. No bus daemon, no NetworkManager, no BlueZ, no media player.
//!
//! What the peer sends is left to the caller: the burst that wedges a service is made of
//! that service's own signals, and only its own match rules will carry them.

use futures_util::StreamExt;
use zbus::{Connection, MessageStream};

/// Two ends of one connection: the peer, and the one a service would be holding.
pub async fn peers() -> (Connection, Connection) {
    let (theirs, ours) = tokio::net::UnixStream::pair().expect("socket pair");
    let guid = zbus::Guid::generate();
    let them = tokio::spawn(async move {
        zbus::connection::Builder::unix_stream(theirs)
            .server(guid)
            .expect("guid")
            .p2p()
            .auth_mechanism(zbus::AuthMechanism::Anonymous)
            .build()
            .await
            .expect("peer")
    });
    let ours = zbus::connection::Builder::unix_stream(ours)
        .p2p()
        .auth_mechanism(zbus::AuthMechanism::Anonymous)
        .build()
        .await
        .expect("ours");
    (them.await.expect("peer task"), ours)
}

/// The peer, listening. Take one of these before emitting anything: a stream only carries
/// what arrives after it exists, and the call under test can land mid-burst.
///
/// Emit the burst on this task, from [`Peer::conn`], and not on the one doing the asking.
/// A peer whose signals are not being read blocks on its own socket once the buffer
/// fills, so a test that floods inline hangs where it should fail.
pub struct Peer {
    conn: Connection,
    incoming: MessageStream,
}

pub async fn listen(conn: Connection) -> Peer {
    let incoming = MessageStream::from(conn.clone());
    Peer { conn, incoming }
}

impl Peer {
    pub fn conn(&self) -> &Connection {
        &self.conn
    }

    /// Answers the first method call it sees, so a test can ask whether a reply still
    /// gets through a burst. Returns once it has answered.
    pub async fn answer_one_call(mut self) {
        while let Some(Ok(message)) = self.incoming.next().await {
            if message.header().message_type() == zbus::message::Type::MethodCall {
                self.conn
                    .reply(&message.header(), &"pong")
                    .await
                    .expect("reply");
                return;
            }
        }
    }
}

/// The call a wedged connection never answers. Fails the test rather than hanging it.
pub async fn ping(conn: &Connection) {
    let reply = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        conn.call_method(
            None::<()>,
            "/probe",
            Some("org.freedesktop.DBus.Peer"),
            "Ping",
            &(),
        ),
    )
    .await
    .expect("the connection wedged: a method reply never arrived past the signal burst")
    .expect("call");
    assert_eq!(reply.body().deserialize::<String>().expect("body"), "pong");
}
