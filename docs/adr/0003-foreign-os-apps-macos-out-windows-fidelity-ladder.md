# Foreign-OS apps: macOS is out; Windows via a fidelity-ordered runtime ladder

> **Extended by [[0010-subsystem-two-axis-trust-driven-isolation]].** The fidelity ladder
> below stands; what changed is that **Windows VM + FreeRDP-RemoteApp (rung 3) is promoted to a
> first-class App Window engine** for semi-trusted/foreign Windows apps — not merely a
> fidelity rung. macOS-out and Wine-as-last-resort are unchanged.

**macOS applications are out of scope as a supported feature.** Apple's macOS SLA permits
virtualization only on Apple-branded hardware, so shipping or advertising a macOS VM on KOOMPI
(non-Apple x86) hardware is a license violation — a product/legal blocker, not a technical one.
The only non-VM path, Darling, is immature (mostly CLI; GUI/Cocoa apps largely do not run) and
is left installable at user discretion only, never supported or marketed.

**Windows applications are supported via a fidelity-ordered, assistant-routed runtime ladder**,
because Wine emulates Win32 widgets and can never reach native-quality UI (partial Wayland,
rough HiDPI, non-native theming/fonts/menus). The ladder, best-fidelity first:

1. **Native Linux app** — preferred whenever one exists.
2. **Web / PWA** — sandboxed, cross-platform, Moat-friendly.
3. **Windows VM + FreeRDP RemoteApp** (WinApps-style: individual Windows app windows rendered
   seamlessly on the KOOMPI desktop) — **perfect fidelity** because Windows does the rendering;
   a **16 GB+ power tier**, needs a Windows license. This is the answer for fidelity-critical
   pro apps (desktop Office, Adobe, CAD), *not* Wine.
4. **Wine/Proton** — light, ~integrated, **mediocre UI**: demoted to last-resort fallback,
   labelled "compatibility, not native UX."

The product promise is **"opens what you need at the best fidelity your hardware allows,"** not
"runs Windows apps." VM-tier egress is filtered with nftables on the VM bridge — the same
allowlist principle as the Subsystem ([[0002-subsystem-containment-bwrap-netns]]), so foreign-OS
apps inherit provable egress containment.

## Consequences

- The VM tier is gated by **The Floor** ([[0001-degrade-local-never-silent-cloud]]): it is a
  16 GB+ feature, never promised on the floor.
- GUI runtimes (Wine, VM+RemoteApp) are the harder GUI tier (Wayland/portal/scaling); the
  Subsystem MVP stays CLI/Linux-first.
