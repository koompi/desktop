//! The `org.freedesktop.Notifications` interface itself, and nothing but the wire.
//!
//! Every decision lives in [`crate::service`]; this file only turns the spec's argument list
//! into decided data and hands it over.

use std::sync::Arc;

use zbus::object_server::SignalEmitter;

use crate::hints::Raw;
use crate::service::Inner;

pub(crate) struct Server {
    pub(crate) inner: Arc<Inner>,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Server {
    /// The spec fixes this argument list, so the count is not ours to reduce.
    #[allow(clippy::too_many_arguments)]
    async fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: Raw,
        expire_timeout: i32,
    ) -> u32 {
        self.inner
            .notify(
                app_name,
                replaces_id,
                app_icon,
                summary,
                body,
                &actions,
                &hints,
                expire_timeout,
            )
            .await
    }

    /// An id nobody holds is not an error here. The spec asks for one, applications send
    /// stale ids constantly, and refusing them tells the sender nothing it can act on.
    async fn close_notification(&self, id: u32) {
        self.inner.close(id, crate::CloseReason::Closed).await;
    }

    fn get_capabilities(&self) -> Vec<String> {
        self.inner.config.capabilities.clone()
    }

    /// Name, vendor, version, and the spec version this server answers to.
    fn get_server_information(&self) -> (String, String, String, String) {
        (
            "koompi-notifications".to_owned(),
            "KOOMPI".to_owned(),
            env!("CARGO_PKG_VERSION").to_owned(),
            "1.2".to_owned(),
        )
    }

    #[zbus(signal)]
    pub(crate) async fn notification_closed(
        emitter: &SignalEmitter<'_>,
        id: u32,
        reason: u32,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    pub(crate) async fn action_invoked(
        emitter: &SignalEmitter<'_>,
        id: u32,
        action_key: &str,
    ) -> zbus::Result<()>;
}
