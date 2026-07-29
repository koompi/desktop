# Telegram Widget — Scope (Zig + libtdjson daemon)

A Telegram tab in the left sidebar, mirroring the AI Chat pattern. Backend is a
tiny compiled Zig daemon wrapping Telegram's official **tdlib** (C JSON
interface); all chat/auth logic lives in QML/JS so it hot-reloads.

---

## v1 boundary (build this, nothing more)

1. **Login panel** — phone → SMS code → 2FA password (driven by tdlib auth states)
2. **Chat list** — your dialogs, most-recent first, name + last message
3. **Open chat** — load + display recent *text* message history
4. **Send text** — type + send to the open chat
5. **Live receive** — new messages append in real time

**Out of scope (v2+):** media/photos/stickers/files, replies, reactions, edits,
typing indicators, read receipts, search, group member mgmt, voice, polls,
multi-account. List exists so the project converges — "Telegram as a widget" is
otherwise unbounded.

---

## Hard prerequisites (user action — can't be coded around)

- **`api_id` + `api_hash`** from <https://my.telegram.org> → API development tools.
  Tied to the user's account. Blocker before anything connects.
- **`database_encryption_key`** — tdlib encrypts its on-disk session DB with a
  key you supply. Empty key = session sits unprotected on disk. Generate one,
  store in `KeyringStorage` alongside `api_hash`.

---

## Part A — tdlib build

Not in Arch sync repos. Build from source (or AUR `tdlib`).

Deps: `cmake gperf openssl zlib` + C++ compiler.

```sh
git clone https://github.com/tdlib/td.git
cd td && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local ..
cmake --build . --target install -- -j1   # -j1/-j2: full build can hit ~8GB RAM, OOMs otherwise
```

Yields `libtdjson.so` + headers (`td/telegram/td_json_client.h`).

⚠️ **Memory** — cap parallelism (`-j1`/`-j2`, Release build). Otherwise OOM.
⚠️ **Install prefix** — if non-standard, runtime needs rpath or `LD_LIBRARY_PATH`,
   else daemon fails to load the `.so`.

---

## Part B — Zig daemon (`tg-daemon`)

**Dumb pipe. ~80 lines.** No Telegram logic — that's the whole point: keeps the
binary trivial and lets all real logic hot-reload in QML.

- `@cImport` `td/telegram/td_json_client.h`
- Startup: `td_execute("{setLogVerbosityLevel level 1}")` (low — keep
  phone/code/2FA/messages out of tdlib logs), then `td_create_client_id()`
- **Reader thread:** loop `td_receive(timeout)` → write each event JSON to stdout,
  `\n`-delimited, **flush after every line**
- **Main thread:** read stdin lines → `td_send(client_id, line)` verbatim

`build.zig`: `linkLibC()`, add tdlib include/lib paths, `linkSystemLibrary("tdjson")`,
set rpath to the install prefix. We call only C symbols, so libtdjson's
`DT_NEEDED` pulls libstdc++/ssl/crypto/z transitively — no explicit C++ link
needed (verify at link time).

### Daemon gotchas (decisions on paper, not debugging later)
- **Flush stdout per line** — `SplitParser` won't see events until flushed;
  default buffering looks like a hang.
- **`td_receive` pointer lifetime** — returned `const char*` valid only until the
  next `td_receive` on that thread. Write to stdout on the *same* thread before
  looping. Never pass the pointer across threads.
- **Single consumer** — exactly one reader thread calling `td_receive`. `td_send`
  from the other thread is fine; never call `td_receive` concurrently.
- **Large lines** — a chat-history event is big; both sides must handle long lines.

---

## Part C — QML service (`services/Telegram.qml`, singleton)

Mirrors `services/Ai.qml` + its `requester`/`SplitParser`, but the `Process` is
**long-lived** (not per-request).

- `Process { command: ["<abs>/tg-daemon"]; stdinEnabled: true }`
- `SplitParser { splitMarker: "\n"; onRead: parseEvent(JSON.parse(line)) }`
- State: `authState`, `chats[]`, `messagesByChat{}`, `currentChatId`
- `sendCommand(obj)` → `process.write(JSON.stringify(obj) + "\n")`
- **`@extra` correlation** — stamp `"@extra": "<id>"` on each request; tdlib echoes
  it on the response. Lets QML match replies (e.g. `getChatHistory`) without the
  daemon parsing anything. Reinforces dumb-pipe.
- Helpers: `setPhone/setCode/setPassword`, `loadChats`, `openChat(id)`
  (→ `getChatHistory`), `sendMessage(chatId, text)` (→ `sendMessage`)
- Auth driver: on `updateAuthorizationState`, react to
  `waitTdlibParameters → setTdlibParameters` (api_id/hash, db dir, db
  encryption key, system info) → `waitPhoneNumber → waitCode → waitPassword →
  ready`. After `ready`, `updateNewMessage`/`updateNewChat` flow in.

⚠️ **tdlib API shapes are version-specific — verify against the *built* version,
   not memory.** Auth-state strings and especially `setTdlibParameters` (params
   were flattened; the old separate `checkDatabaseEncryptionKey` step was folded
   in during 1.8.x) differ across releases. Pin shapes to the built tdlib's
   `td/generate/scheme/td_api.tl` / matching td_api docs at implementation time.

Storage: session DB under `~/.local/share/quickshell/koompi/tdlib/`. `api_hash` +
`database_encryption_key` in `KeyringStorage`. `api_id` in config.

---

## Part D — UI (`modules/koompi/sidebarLeft/`)

- `TelegramChat.qml` — container; switches login panel ↔ chat-list ↔ conversation
  on `authState`/`currentChatId`
- `telegram/LoginPanel.qml` — phone/code/2FA fields bound to auth state
- `telegram/ChatListItem.qml` — name + last-message row
- `telegram/TelegramMessage.qml` — bubble (sender, time, text); clone
  `aiChat/AiMessage.qml` layout
- Conversation view: `StyledListView` of messages + input area (reuse AiChat's
  input lines)

Register: add to `SidebarLeftContent.qml` `tabButtonList` + `contentChildren`,
gated on `Config.options.policies.telegram`. Bar toggle already exists.

---

## Effort

| Part | Estimate |
|---|---|
| A — tdlib build | ~0.5–1h (mostly compile wait) |
| B — Zig daemon + build.zig/link | ~half day |
| C — Telegram.qml service + auth driver | ~1 day |
| D — UI (login + list + convo + renderer) | ~1–2 days |

Realistically a few focused days. tdlib build + Zig link are the front-loaded
unknowns; once the daemon emits events to stdout, the rest is the familiar
AiChat pattern.

---

## Suggested build order (each step independently verifiable)

1. Build tdlib → confirm `libtdjson.so` loads.
2. Zig daemon → run by hand, paste a `setTdlibParameters` JSON on stdin, see the
   auth-state event come back on stdout. Proves the pipe end-to-end.
3. `Telegram.qml` auth driver → log in via `qs -c koompi log`, reach
   `authorizationStateReady`.
4. Chat list → `loadChats`, render.
5. Open chat + history + send.
6. UI polish + tab registration.
