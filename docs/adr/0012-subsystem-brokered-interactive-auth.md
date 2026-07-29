# Subsystem interactive auth is brokered: host-browser interception, device-code preferred, callback-relay mandatory

When an app inside a Subsystem context must perform an **interactive login** (OAuth /
OpenID-Connect / device-code), the **Broker** (`koompi-brokerd`, [[0011-subsystem-credential-broker]])
runs the entire flow **host-side** and the context performs **no** auth I/O of its own. The
default is **host-browser interception** — the user authenticates in their own trusted browser,
never inside the context. **Device-code (RFC 8628) is preferred** where the provider supports it;
a **localhost-callback relay is mandatory** for apps that only support a loopback redirect (the
Claude Code class). This is the interactive-auth half of the broker contract; the credential
storage / egress-injection half is [[0011-subsystem-credential-broker]].

## Why this is not optional plumbing — the network facts that force it

A context's network identity is *not* the host's, and the gap breaks the naive OAuth assumption
that "the app opens `http://localhost:PORT` and the redirect just arrives":

- **bwrap + per-netns:** a per-context network namespace has its **own loopback** — a redirect
  to `127.0.0.1:PORT` inside the context cannot reach a listener the host (or the user's browser)
  can see, and vice-versa. *(Pathname `AF_UNIX` sockets cross namespaces and are the relay
  channel; **abstract `@`-sockets are netns-scoped and must not be used** for this.)*
- **microVM / VM:** the guest has an **entirely separate network stack** — its `localhost` is
  not the host's at all. The gap is wider, not narrower, than the netns case.
- **The browser lives on the host.** The user's real browser (with their real, trusted sessions)
  runs in the host session, not in the context. So *some* host↔context bridge is unavoidable for
  any interactive flow — the only question is whether the Broker owns it or each context
  improvises one.

**Device-code sidesteps the loopback problem entirely** (the user visits a URL and types a code;
there is no redirect to catch), which is why it is preferred — it is identical across bwrap-netns
and VM guests. But it is **not universal**: Claude Code supports **only** a localhost callback
(no device-code; upstream issue #7100 closed *not-planned*), so a callback relay is **mandatory**,
not a nicety, for that class.

## The decision

1. **Host-browser interception (default).** The context has no browser. An `xdg-open` / `$BROWSER`
   shim in the context forwards any auth-URL open to the Broker over the per-context broker
   channel (pathname socket for bwrap, vsock for VM contexts —
   [[0011-subsystem-credential-broker]]); the Broker opens the URL in the **user's host browser**.
   The user authenticates in
   their trusted browser, so the context never sees the user's provider session cookies — only
   the resulting scoped token (and only if the trust tier permits a token at all; an untrusted
   context gets a Deputy connection, not the token).
2. **Device-code preferred.** Where the provider offers RFC 8628, the Broker uses it: it shows
   the user the verification URL + code (host-side UI), the user approves in the host browser,
   the Broker polls the token endpoint. No loopback, no relay.
3. **Callback relay mandatory (fallback).** For loopback-only apps, the Broker runs the
   **host-side** loopback listener, the context's `localhost:PORT` redirect is relayed to it over
   the per-context broker channel, the Broker captures the authorization code, performs the token exchange,
   and writes the result to the per-context store ([[0011-subsystem-credential-broker]]).

## Invariants (the broker contract for auth)

1. **The Broker does ALL auth I/O** — browser launch, callback capture, token exchange, refresh.
   The context never opens a browser, never listens for a callback, never holds a client secret.
2. **Broker-constructed URLs from templates only** — the Broker builds the authorization URL from
   a vetted per-provider template; it **never** opens a URL the context hands it verbatim. This is
   the anti-phishing line: a malicious context must not be able to drive the user's trusted
   browser to an attacker URL under cover of "logging in."
3. **Host-attested context identity** — the Broker identifies the requesting context by a
   mechanism the **host** controls, never by a name the context asserts: **`SO_PEERCRED`** on the
   pathname socket for bwrap contexts, the **host-assigned vsock CID** for VM contexts (interactive
   auth applies to bwrap + semi-trusted microVM contexts; the hermetic Detonation Chamber runs no
   brokered login). *(Per-engine mechanism settled in [[0011-subsystem-credential-broker]].)*
4. **Per-context credential store** — the issued token lands in the per-context store, never the
   shared keyring. *(Settled in [[0011-subsystem-credential-broker]].)*
5. **Write-ahead ledger** — every auth event (URL opened, code received, token issued/refreshed,
   for which context) is appended to the host-side ledger before the token is handed back, so a
   login is auditable even if the context is later disposed.

## Honest limit (the analogue of the deputy's pinning gap)

An app with its **own embedded webview** (some Windows/RemoteApp apps; some microVM GUI apps)
does its login *inside* its own UI and never calls `xdg-open`, so the Broker **cannot intercept
it** — the auth then happens inside the guest, which sees that session. This is:

- **acceptable for semi-trusted App Window** — the guest is VM-isolated, so the session is
  confined to a disposable, contained guest;
- **irrelevant for the Detonation Chamber** — an untrusted context holds no real credentials by
  design, and a user who logs a real account into an embedded webview there is knowingly burning
  that session;
- **stated, not hidden** — like the deputy's cert-pinning gap, this is a real edge of the
  guarantee, disclosed rather than papered over.

## Relationships

- **Completes the broker contract of [[0011-subsystem-credential-broker]]** — same daemon, same
  five invariants; 0011 covers credentials at rest + egress injection, this covers interactive
  login.
- **Operates within the modes of [[0010-subsystem-two-axis-trust-driven-isolation]]** — the trust
  tier decides whether a successful login yields an in-context token (Light/App Window) or only a
  host-side Deputy connection (untrusted).
- **Lands in Track S, S-1** (the Broker) in the roadmap.

## Consequences

- The Broker needs three host-side facilities per context: an auth-URL handler, a loopback
  callback listener, and token-exchange/refresh logic — non-trivial, accepted as the only way to
  keep login in the trusted host browser and secrets out of the context.
- The context image must ship the `xdg-open`/`$BROWSER` shim and must **not** ship a real browser
  for auth purposes.
- A provider that supports neither device-code nor a redirect the Broker can relay (e.g. a
  hard-coded public-client flow with an embedded webview) falls under the honest-limit clause and
  must be labelled as such, never silently treated as fully brokered.
