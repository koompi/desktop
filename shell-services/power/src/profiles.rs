//! D12: the power-profiles-daemon side of `PowerSaving.qml`.

use koompi_service::{Error, Result};

use crate::props::{self, Props};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    PowerSaver,
    Balanced,
    Performance,
}

impl Profile {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::PowerSaver => "power-saver",
            Self::Balanced => "balanced",
            Self::Performance => "performance",
        }
    }

    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "power-saver" => Some(Self::PowerSaver),
            "balanced" => Some(Self::Balanced),
            "performance" => Some(Self::Performance),
            _ => None,
        }
    }
}

/// `active` is None only when the daemon names a profile this build does not model,
/// which keeps one unrecognised string from failing the whole read.
#[derive(Debug, Clone, PartialEq)]
pub struct Profiles {
    pub active: Option<Profile>,
    pub available: Vec<Profile>,
    /// `PerformanceDegraded`: non-empty names the reason, usually `lap-detected`.
    pub degraded: Option<String>,
}

impl Profiles {
    pub(crate) fn from_props(props: &Props) -> Self {
        Self {
            active: props::text(props, "ActiveProfile")
                .as_deref()
                .and_then(Profile::parse),
            available: available_from(props),
            degraded: props::text(props, "PerformanceDegraded").filter(|r| !r.is_empty()),
        }
    }
}

fn available_from(props: &Props) -> Vec<Profile> {
    let Some(value) = props.get("Profiles") else {
        return Vec::new();
    };
    let Ok(entries) = value.downcast_ref::<&zvariant::Array>() else {
        return Vec::new();
    };
    entries
        .iter()
        .filter_map(|entry| Props::try_from(entry.try_clone().ok()?).ok())
        .filter_map(|entry| props::text(&entry, "Profile"))
        .filter_map(|name| Profile::parse(&name))
        .collect()
}

pub(crate) fn unavailable<T>() -> Result<T> {
    Err(Error::Unavailable("power-profiles-daemon".into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use zvariant::{OwnedValue, Value};

    fn entry(name: &str) -> Props {
        HashMap::from([(
            "Profile".to_owned(),
            OwnedValue::try_from(Value::from(name)).unwrap(),
        )])
    }

    /// The shape `busctl get-property ... Profiles` returns on this seat: three
    /// dicts, each with a `Profile` string beside driver names we do not model.
    #[test]
    fn the_daemons_profile_list_reads_back_as_the_three_it_offers() {
        let listed = vec![
            entry("power-saver"),
            entry("balanced"),
            entry("performance"),
        ];
        let props = Props::from([
            (
                "Profiles".to_owned(),
                OwnedValue::try_from(Value::from(listed)).unwrap(),
            ),
            (
                "ActiveProfile".to_owned(),
                OwnedValue::try_from(Value::from("balanced")).unwrap(),
            ),
            (
                "PerformanceDegraded".to_owned(),
                OwnedValue::try_from(Value::from("")).unwrap(),
            ),
        ]);

        let profiles = Profiles::from_props(&props);

        assert_eq!(profiles.active, Some(Profile::Balanced));
        assert_eq!(
            profiles.available,
            [Profile::PowerSaver, Profile::Balanced, Profile::Performance]
        );
        assert_eq!(profiles.degraded, None);
    }

    #[test]
    fn a_profile_name_we_do_not_model_leaves_active_unset_rather_than_failing() {
        let props = Props::from([(
            "ActiveProfile".to_owned(),
            OwnedValue::try_from(Value::from("quiet")).unwrap(),
        )]);

        assert_eq!(Profiles::from_props(&props).active, None);
    }
}
