# Rust for the thinks-stack daemons; Zig stays for installer/restore (dual toolchain)

The L1–L4 thinks-stack daemons (`koompi-contextd`, `koompi-assistantd`, `koompi-busd`,
`koompi-policyd`) are written in **Rust**, while the **installer and `koompi-restore` stay
Zig** and the shell stays QML/Quickshell — a deliberate dual-toolchain commitment.

We chose Rust on **ecosystem** grounds, *not* language properties: Zig is also
memory-safe-ish / no-GC / small-RSS and is being kept anyway, so that is not the
discriminator. The daemons need mature async **D-Bus (`zbus`)**, **TLS/HTTP
(`rustls`/`reqwest`)**, **SQLite + vector bindings (`rusqlite`/`sqlite-vec`)**, and **CRDT
(`Automerge`)** — all first-class in Rust, all hand-rolled or FFI'd in Zig.

The trade-off is a second toolchain for ~5 years and a dual-toolchain CI (`zig build` +
`cargo build` + `cargo deny`, roadmap X-9). We accept it because the alternative — a
one-language shop — would mean *either* rewriting the just-migrated (Zig 0.16) installer in
Rust, *or* rebuilding the async-D-Bus / TLS / CRDT stack by hand in Zig. The ecosystem is the
reason; name it as such, not as "we need native memory-safe code."
