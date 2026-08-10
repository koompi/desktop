use std::collections::HashMap;

use futures_util::StreamExt;
use koompi_service::{Error, Result, Service};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use zbus::fdo::{InterfacesAdded, InterfacesRemoved, ObjectManagerProxy};
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, Message, MessageStream};
use zvariant::{ObjectPath, OwnedValue};

use crate::model::{Adapter, Device};
use crate::objects::Objects;
use crate::props::Props;
use crate::proxy::{AdapterProxy, DeviceProxy};
use crate::rfkill::{self, RfkillState};

const BLUEZ: &str = "org.bluez";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BluetoothState {
    pub adapters: Vec<Adapter>,
    pub devices: Vec<Device>,
    pub rfkill: RfkillState,
}

impl BluetoothState {
    /// `BluetoothStatus.qml:12` decides this from the adapter count, and a seat with no
    /// adapter is a working seat.
    pub fn available(&self) -> bool {
        !self.adapters.is_empty()
    }

    pub fn default_adapter(&self) -> Option<&Adapter> {
        self.adapters.first()
    }

    pub fn powered(&self) -> bool {
        self.default_adapter()
            .is_some_and(|adapter| adapter.powered)
    }

    pub fn device(&self, path: &str) -> Option<&Device> {
        self.devices.iter().find(|device| device.path == path)
    }
}

pub struct BluetoothService {
    conn: Connection,
    rx: watch::Receiver<BluetoothState>,
    task: JoinHandle<()>,
}

impl Service for BluetoothService {
    type State = BluetoothState;

    fn state(&self) -> BluetoothState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<BluetoothState> {
        self.rx.clone()
    }
}

impl Drop for BluetoothService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl BluetoothService {
    pub async fn connect() -> Result<Self> {
        Self::with_connection(Connection::system().await?).await
    }

    pub async fn with_connection(conn: Connection) -> Result<Self> {
        let manager = ObjectManagerProxy::builder(&conn)
            .destination(BLUEZ)?
            .path("/")?
            .build()
            .await?;

        let mut objects = Objects::default();
        let managed = manager
            .get_managed_objects()
            .await
            .map_err(|error| Error::Bus(error.into()))?;
        for (path, interfaces) in managed {
            objects.add(path.as_str(), owned_interfaces(interfaces));
        }

        // A device the seat user cannot open is a bluetooth toggle that cannot be
        // trusted, not a service that failed to start.
        let reader = rfkill::Reader::open().ok();

        let (tx, rx) = watch::channel(snapshot(
            &objects,
            reader.as_ref().map(rfkill::Reader::state),
        ));
        let task = tokio::spawn(run(conn.clone(), manager, objects, reader, tx));

        Ok(Self { conn, rx, task })
    }

    pub fn adapter(&self) -> Result<Adapter> {
        self.rx
            .borrow()
            .default_adapter()
            .cloned()
            .ok_or_else(|| Error::Unavailable("bluetooth adapter".into()))
    }

    /// `BluetoothStatus.qml:17-23`: on unblocks first because BlueZ reports success on a
    /// soft-blocked adapter and leaves it off, off is the property alone.
    pub async fn set_powered(&self, powered: bool) -> Result<()> {
        let adapter = self.adapter()?;

        if powered {
            let rfkill = self.rx.borrow().rfkill.clone();
            if rfkill.hard_blocked() {
                return Err(Error::Unavailable(
                    "bluetooth radio, blocked by a hardware switch".into(),
                ));
            }
            match rfkill::unblock_bluetooth() {
                Ok(()) => {}
                // Nothing to clear, so an unreachable `/dev/rfkill` changes no outcome.
                Err(_) if !rfkill.soft_blocked() => {}
                Err(error) => return Err(error),
            }
        }

        self.adapter_proxy(&adapter.path)
            .await?
            .set_powered(powered)
            .await?;
        Ok(())
    }

    pub async fn start_discovery(&self) -> Result<()> {
        let adapter = self.adapter()?;
        self.adapter_proxy(&adapter.path)
            .await?
            .start_discovery()
            .await?;
        Ok(())
    }

    pub async fn stop_discovery(&self) -> Result<()> {
        let adapter = self.adapter()?;
        self.adapter_proxy(&adapter.path)
            .await?
            .stop_discovery()
            .await?;
        Ok(())
    }

    pub async fn connect_device(&self, path: &str) -> Result<()> {
        self.device_proxy(path).await?.connect().await?;
        Ok(())
    }

    pub async fn disconnect_device(&self, path: &str) -> Result<()> {
        self.device_proxy(path).await?.disconnect().await?;
        Ok(())
    }

    pub async fn pair(&self, path: &str) -> Result<()> {
        self.device_proxy(path).await?.pair().await?;
        Ok(())
    }

    pub async fn cancel_pairing(&self, path: &str) -> Result<()> {
        self.device_proxy(path).await?.cancel_pairing().await?;
        Ok(())
    }

    pub async fn set_trusted(&self, path: &str, trusted: bool) -> Result<()> {
        self.device_proxy(path).await?.set_trusted(trusted).await?;
        Ok(())
    }

    /// `RemoveDevice` belongs to the adapter, and the device's own object path is where
    /// the adapter to ask lives.
    pub async fn remove_device(&self, path: &str) -> Result<()> {
        let device = ObjectPath::try_from(path.to_owned())
            .map_err(|error| Error::Protocol(error.to_string()))?;
        let adapter = self
            .rx
            .borrow()
            .device(path)
            .map(|device| device.adapter.clone())
            .ok_or_else(|| Error::Unavailable(format!("device {path}")))?;

        self.adapter_proxy(&adapter)
            .await?
            .remove_device(&device)
            .await?;
        Ok(())
    }

    async fn adapter_proxy(&self, path: &str) -> Result<AdapterProxy<'_>> {
        Ok(AdapterProxy::builder(&self.conn)
            .destination(BLUEZ)?
            .path(path.to_owned())?
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }

    async fn device_proxy(&self, path: &str) -> Result<DeviceProxy<'_>> {
        Ok(DeviceProxy::builder(&self.conn)
            .destination(BLUEZ)?
            .path(path.to_owned())?
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }
}

fn snapshot(objects: &Objects, rfkill: Option<&RfkillState>) -> BluetoothState {
    BluetoothState {
        adapters: objects.adapters(),
        devices: objects.devices(),
        rfkill: rfkill.cloned().unwrap_or_default(),
    }
}

fn owned_interfaces(
    interfaces: HashMap<zbus::names::OwnedInterfaceName, Props>,
) -> HashMap<String, Props> {
    interfaces
        .into_iter()
        .map(|(name, props)| (name.to_string(), props))
        .collect()
}

async fn run(
    conn: Connection,
    manager: ObjectManagerProxy<'static>,
    mut objects: Objects,
    mut reader: Option<rfkill::Reader>,
    tx: watch::Sender<BluetoothState>,
) {
    let (Ok(mut added), Ok(mut removed), Ok(mut changed)) = (
        manager.receive_interfaces_added().await,
        manager.receive_interfaces_removed().await,
        properties_changed(&conn).await,
    ) else {
        return;
    };

    loop {
        let dirty = tokio::select! {
            Some(signal) = added.next() => apply_added(&mut objects, &signal),
            Some(signal) = removed.next() => apply_removed(&mut objects, &signal),
            Some(Ok(message)) = changed.next() => apply_changed(&mut objects, &message),
            Some(()) = next_rfkill(&mut reader) => true,
            else => return,
        };

        if dirty {
            let state = snapshot(&objects, reader.as_ref().map(rfkill::Reader::state));
            tx.send_if_modified(|current| {
                let moved = *current != state;
                if moved {
                    *current = state;
                }
                moved
            });
        }
    }
}

/// One rule for every `PropertiesChanged` BlueZ sends. Subscribing per object would
/// leave a device discovered a moment later unsubscribed.
async fn properties_changed(conn: &Connection) -> zbus::Result<MessageStream> {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(BLUEZ)?
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .build();
    MessageStream::for_match_rule(rule, conn, Some(64)).await
}

fn apply_added(objects: &mut Objects, signal: &InterfacesAdded) -> bool {
    let Ok(args) = signal.args() else {
        return false;
    };
    let interfaces = args
        .interfaces_and_properties
        .iter()
        .map(|(name, props)| (name.to_string(), owned_props(props)))
        .collect();
    objects.add(args.object_path.as_str(), interfaces)
}

fn apply_removed(objects: &mut Objects, signal: &InterfacesRemoved) -> bool {
    let Ok(args) = signal.args() else {
        return false;
    };
    let interfaces: Vec<String> = args
        .interfaces
        .iter()
        .map(|name| name.to_string())
        .collect();
    objects.remove(args.object_path.as_str(), &interfaces)
}

fn apply_changed(objects: &mut Objects, message: &Message) -> bool {
    let header = message.header();
    let Some(path) = header.path().map(|path| path.to_string()) else {
        return false;
    };
    let Ok((interface, changed, invalidated)) =
        message.body().deserialize::<(String, Props, Vec<String>)>()
    else {
        return false;
    };
    objects.merge(&path, &interface, changed, &invalidated)
}

/// A seat where `/dev/rfkill` never opened has no rfkill branch to wake on, and one that
/// stopped reading loses the branch rather than spinning on the error.
async fn next_rfkill(reader: &mut Option<rfkill::Reader>) -> Option<()> {
    let Some(inner) = reader.as_mut() else {
        return std::future::pending().await;
    };
    if inner.changed().await.is_err() {
        *reader = None;
    }
    Some(())
}

fn owned_props(props: &HashMap<&str, zvariant::Value<'_>>) -> Props {
    props
        .iter()
        .filter_map(|(key, value)| {
            OwnedValue::try_from(value.try_clone().ok()?)
                .ok()
                .map(|value| ((*key).to_owned(), value))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::names::InterfaceName;

    const ADAPTER: &str = "/org/bluez/hci0";
    const DEVICE: &str = "/org/bluez/hci0/dev_AC_80_0A_11_22_33";

    fn call(path: &str, interface: &str, member: &str) -> Message {
        Message::method_call(path, member)
            .unwrap()
            .destination(BLUEZ)
            .unwrap()
            .interface(interface)
            .unwrap()
            .build(&())
            .unwrap()
    }

    /// None of these are fired against this seat, which has no paired device, so the
    /// wire form is what gets checked: the same messages `bluetoothctl` puts on the bus.
    #[test]
    fn every_device_command_addresses_the_device_object_on_device1() {
        for member in ["Connect", "Disconnect", "Pair", "CancelPairing"] {
            let message = call(DEVICE, "org.bluez.Device1", member);
            let header = message.header();

            assert_eq!(header.path().unwrap().as_str(), DEVICE);
            assert_eq!(header.interface().unwrap(), "org.bluez.Device1");
            assert_eq!(header.member().unwrap(), member);
            assert_eq!(message.body().signature().to_string(), "");
        }
    }

    #[test]
    fn discovery_addresses_the_adapter_object_on_adapter1() {
        for member in ["StartDiscovery", "StopDiscovery"] {
            let message = call(ADAPTER, "org.bluez.Adapter1", member);
            let header = message.header();

            assert_eq!(header.path().unwrap().as_str(), ADAPTER);
            assert_eq!(header.interface().unwrap(), "org.bluez.Adapter1");
            assert_eq!(header.member().unwrap(), member);
        }
    }

    /// The one command whose object is not the object it names.
    #[test]
    fn remove_device_goes_to_the_adapter_and_carries_the_device_as_its_argument() {
        let device = ObjectPath::try_from(DEVICE).unwrap();
        let message = Message::method_call(ADAPTER, "RemoveDevice")
            .unwrap()
            .destination(BLUEZ)
            .unwrap()
            .interface("org.bluez.Adapter1")
            .unwrap()
            .build(&(&device,))
            .unwrap();

        let header = message.header();
        assert_eq!(header.path().unwrap().as_str(), ADAPTER);
        assert_eq!(message.body().signature().to_string(), "o");
        assert_eq!(
            message.body().deserialize::<ObjectPath<'_>>().unwrap(),
            device
        );
    }

    /// `Powered` and `Trusted` are properties, so they travel as `Properties.Set` with a
    /// boolean variant rather than as methods of their own.
    #[test]
    fn the_writable_properties_travel_as_a_properties_set() {
        for (path, interface, property) in [
            (ADAPTER, "org.bluez.Adapter1", "Powered"),
            (DEVICE, "org.bluez.Device1", "Trusted"),
        ] {
            let message = Message::method_call(path, "Set")
                .unwrap()
                .destination(BLUEZ)
                .unwrap()
                .interface("org.freedesktop.DBus.Properties")
                .unwrap()
                .build(&(
                    InterfaceName::try_from(interface).unwrap(),
                    property,
                    zvariant::Value::from(true),
                ))
                .unwrap();

            let body = message.body();
            assert_eq!(body.signature().to_string(), "(ssv)");
            let (iface, name, value): (String, String, zvariant::Value<'_>) =
                body.deserialize().unwrap();
            assert_eq!(iface, interface);
            assert_eq!(name, property);
            assert!(bool::try_from(value).unwrap());
        }
    }

    #[test]
    fn a_seat_with_no_adapter_is_unavailable_rather_than_broken() {
        let state = BluetoothState::default();

        assert!(!state.available());
        assert!(!state.powered());
        assert!(state.default_adapter().is_none());
    }
}
