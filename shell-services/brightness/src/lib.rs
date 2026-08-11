//! D15 brightness: logind `SetBrightness` for the internal panel, which removes the udev
//! rule and the root requirement; `ddcutil` stays for external ones.
//!
//! The two backends keep the two write rules `Brightness.qml` used: a whole-percent step
//! with a floor of one raw unit for the internal panel, the fraction scaled straight onto
//! the reported max for DDC, and a 300 ms debounce on DDC alone.
//!
//! The anti-flashbang capture and `Hyprsunset` gamma stay out. A multiplier computed
//! elsewhere comes in through `set_multiplier` and is clamped here.

mod ddc;
mod logind;
mod panel;
mod service;
mod sysfs;
mod writer;

pub use panel::{Backend, Panel};
pub use service::{BrightnessService, BrightnessState};
