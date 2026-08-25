# J08 report — split AiChat.qml into composer, transcript, commands, completion (AUDIT D8)

Branch `j08-split-aichat`, rebased onto main `c4d3c41b` (the lead's mid-job request; it was `86c616f5` when the work and the live checks were done, and main touched nothing under `sidebarLeft/`).
Commit `fcbd02e8` is the split plus the allow-list row; this report is the second commit.
Files touched: `modules/koompi/sidebarLeft/AiChat.qml` (1389 → 184 lines), seven new files under `modules/koompi/sidebarLeft/aiChat/`, `tests/file-length-allow.txt` (one row removed), this file.
Nothing outside the owned list was edited; both stop conditions were checked and neither fired (details under "Contract").

Live deploy backups: `/tmp/j08-HV0yEy/orig/AiChat.qml` (the one file overwritten, sha256 `3dbe83a703a68169…`) and `/tmp/j08-HV0yEy/orig/sidebarLeft-full/` (the whole live directory as it was).
Also under `/tmp/j08-HV0yEy/`: `states.json.orig` and `chats-backup/` (see "Live-desktop side effects"), the screenshots, the log captures, and the two typing helpers.

## Two things the lead should know first

1. **Stray keystrokes reached the lead's own herdr pane.**
   My first command batch on main used `wtype` without checking that the left sidebar still had focus.
   The sidebar is a `GlobalFocusGrab` dismissable, so it closed the moment something else took focus (Rithy was working), and the rest of the batch went into the focused window: the J18 lead session in wezterm.
   Its transcript shows `Interrupted · What should Claude do instead?` followed by a prompt `//////load` being sent (screenshot `/tmp/j08-HV0yEy/shot1.png`).
   I cannot tell which of `/clear /save /load /compact …` Claude Code's slash menu swallowed before that; the visible context (389k) suggests `/clear` did not run there, but please check that session.
   After that every keystroke went through `/tmp/j08-HV0yEy/type.sh` / `key.sh`, which refuse to type unless the `quickshell:sidebarLeft` layer is mapped and withhold Return if it unmapped meanwhile.
   One later batch (Tab/Escape/PageUp/PageDown, and the first eight characters of `capital of Cambodia`) still leaked to Rithy's Chrome window during the race; harmless there, but it happened.
   The stall and starter demos were therefore done with zero keystrokes (mouse click on the chip, endpoint through the watched state file).
2. **`/model` with no argument is destructive on main** (severity: medium, user-visible data change).
   `ChatCommands` passes `args[0]` straight to `Ai.setModel`, and `ModelRegistry.setModel("")` takes the "any unrecognised name is a remote model" branch: it set `ai.model=remote`, `remoteModel=""` and wiped `remoteEndpoint` on Rithy's live state when I typed it for the main baseline.
   I restored all three with `/model gemini-flash-latest`, `/endpoint remote http://127.0.0.1:9998/v1/chat/completions`, `/model local` and verified `states.json` matches the pre-run snapshot.
   Not fixed: the root cause is in `services/ai/ModelRegistry.qml` (out of scope), and guarding it in the command would change a command's behaviour, which D8 forbids.
   On the new build I typed `/model local` instead, so the table row compares the first line (the "lives in Settings" note), which is the same either way.

## How the split is cut

| file | from AiChat.qml | what it is |
|---|---|---|
| `aiChat/ChatCommands.qml` (QtObject) | 56–495 | `prefix`, `commandGroups`, `groupTitleOf`, `noteThatItMoved`, `allCommands` (22 entries, verbatim), `run(name, args) → bool` |
| `aiChat/testMessage.js` | 443–492 | the `/test` fixture as `text(iconSource, iconHeight)`; the two `${…}` that needed `Quickshell`/`Appearance` became the parameters |
| `aiChat/CommandCompletion.qml` (QtObject) | 605–711 | `commands` in, `query`/`entries` out; `argumentCandidates`, `commandEntries`, `narrow`, `byGroup`, `updateSuggestions(text)` |
| `aiChat/ChatTranscript.qml` (Item) | 739–902 + 497, 525–532, 545–560 | list, status bar, placeholder, starters, scroll button, stall watchdog; `focusTranscript()`, `positionAtEnd()`, `positionAtBeginning()`, `pageUp()`, `pageDown()`; signals `starterChosen`, `settingsRequested`, `composerFocusRequested` |
| `aiChat/ChatComposer.qml` (ColumnLayout) | 713–729, 952–983, 1068–1387, 504–517, 534–543 | field, send button, toolbar, description box + palette, activity panel, paste/attach process, history; `text`, `prefix`, `helpShown`, `attachMenuShown`, `suggestionsVisible`, `prefill`, `insertText`, `focusInput`, `focusNext`, `submit`; signals `submitted`, `transcriptFocusRequested`, `pageScrollRequested(dir)`, `settingsRequested`, `retryRequested` |
| `aiChat/RecallStrip.qml` (ColumnLayout) | 498–500, 562–578, 985–1025, 1128–1138 | debounce timer + strip; `noteTyping(text)`, `reset()` |
| `aiChat/ContextMeter.qml` (ColumnLayout) | 904–950 | fill bar + "nearly full" line |
| `AiChat.qml` | 16–54, 519–523, 580–603, 1027–1066 | root key handling, `openAiSettings`, `submit` (the dispatch half of the old `handleInput`), undo-clear bar, help sheet, attach menu, the six children and their wiring |

### Contract: what the map missed, and how it was expressed

The map named two id couplings.
Reading the file found four more, all expressible as signals or in-properties, so the "third id coupling" stop condition did not fire:

- transcript → composer: `messageListView.Keys.onPressed` (Esc/Backtab) called `messageInputField.forceActiveFocus()` → signal `composerFocusRequested()`.
- composer → transcript state: Ctrl+R did `Ai.retryRequest(); root.stallDetected = false` → signal `retryRequested()`, routed in AiChat to both.
- transcript → composer text: the starter chips were hidden unless `messageInputField.text.length === 0` → in-property `composerEmpty`.
- composer → chat geometry: `Layout.preferredHeight: Math.min(root.height * 3/5, …)` read the chat's height → in-property `inputHeightLimit`.
- Tab's fallback (`nextItemInFocusChain` when the transcript is empty) needs the result of `focusTranscript()`, which a signal cannot return, so AiChat does `if (!transcript.focusTranscript()) composer.focusNext()`.
- Ctrl+Home also existed in 1166–1181, so `pageScrollRequested(dir)` carries `"up" | "down" | "home" | "end"`, and the transcript gained `positionAtBeginning()`.

`messageInputField` is forwarded to `AiMessage` as the `ChatComposer` item (the full window's `ChatPane` passes its composer the same way); `AiMessage.qml` declares the property and never reads it.

### Deviations from the letter of the map

- Two files did not fit their caps as mapped.
  The command table alone is 381 lines, so `commandGroups` became four one-line entries and the `test` entry three lines (398).
  The composer as mapped was 478 lines; it now holds only what the map assigned plus the palette (whose accept helpers write the field) and the activity panel, with the help sheet, attach menu and undo bar in AiChat.qml, three toolbar icons through one inline `component ToolbarIcon`, five one-line tooltips, and the four scroll keys as one signal each (395).
  Consequence for the column order: the description box and palette now sit below the recall strip, undo bar and sheets instead of above them.
  Palette and recall strip are never visible together (one needs a leading `/`, the other forbids it); the undo bar and the sheets can be, in which case they render above the palette rather than below.
- `Unknown command: X` stays a chat message, not a model turn: `submit()` only calls `Ai.sendUserMessage` for lines that do not start with the prefix, as before.
  The literal `if (!commands.run(...)) Ai.sendUserMessage(...)` from the map would have sent `/typo` to the model.
- Deleted: the composer's `accept()` function (1141–1144).
  `grep -rn "\.accept()"` over the shell finds no caller.
- `koompi reload` was not used: `dots/.local/bin/koompi-reload` does `killall -w -q global-menu-daemon qs quickshell`, which the lead addendum forbids.
  Quickshell watches its own files (`Quickshell.watchFiles`, on by default), so copying into `~/.config/quickshell/koompi` reloads the running instance in place: the log shows `Reloading configuration… / Configuration Loaded` and `qs list` reports the same PID 702039 before and after.
- Two qmllint notes: `/usr/bin/qmllint` is Qt 5 and rejects the tree; `/usr/lib/qt6/bin/qmllint -I <dir with qs → shell root> -I /usr/lib/qt6/qml` (the invocation `tests/test_services_qml_bugs.sh` uses) gives 0 errors on all seven QML files.
  It prints only warnings, all `[import]`/`[unqualified]` resolution noise; main's `AiChat.qml` gets the same kinds through the same invocation.

## Acceptance 1 — line counts

| file | lines | cap |
|---|---|---|
| `AiChat.qml` | 184 | 400 |
| `aiChat/ChatCommands.qml` | 398 | 400 |
| `aiChat/CommandCompletion.qml` | 119 | 400 |
| `aiChat/ChatTranscript.qml` | 224 | 400 |
| `aiChat/ChatComposer.qml` | 395 | 400 |
| `aiChat/RecallStrip.qml` | 92 | 400 |
| `aiChat/ContextMeter.qml` | 57 | 400 |
| `aiChat/testMessage.js` | 59 | 300 |

`./tests/test_file_length.sh` after the rebase → `ok: 902 files under cap, 35 allow-listed and not grown`; the `AiChat.qml 1389` row is gone (it was `ok: 785 files under cap, 32 allow-listed` on the pre-rebase base, 33 → 32 rows).

## Acceptance 2 — every command, live, main vs this branch

Method: the sidebar was opened with `qs ipc -c koompi call sidebarLeft open`, each line typed with `wtype` and Enter, then `/save j08-main` (on main, 15:11) and `/save j08-new` (on this branch, 15:19) wrote the transcripts to `~/.local/state/quickshell/user/ai/chats/`, from which the first non-empty line of each interface reply was read with `jq`.
`/clear` was sent first each time, so `/compact` (fewer than 4 non-interface messages) is silent by design on both, and `/fork` reports "not enough".
Arguments were omitted so nothing else mutates; `/model` is the exception described above.

| # | typed | first response line on main | on this branch |
|---|---|---|---|
| 1 | `/clear` | (chat cleared; "Chat cleared · Undo" bar) | same |
| 2 | `/save` | `Usage: /save CHAT_NAME` | same |
| 3 | `/load` | `Usage: /load CHAT_NAME` | same |
| 4 | `/compact` | (no reply: fewer than 4 non-interface messages) | same |
| 5 | `/fork` | `Not enough messages to fork.` | same |
| 6 | `/resume` | `Usage: /resume SESSION_ID` | same |
| 7 | `/help` | `**This conversation**` | same |
| 8 | `/remember` | `Usage: /remember SOMETHING TO REMEMBER` | same |
| 9 | `/memories` | `**Stored memories** (forget with /forget ID):` | same |
| 10 | `/forget` | `Usage: /forget MEMORY_ID` | same |
| 11 | `/owner` | `You're registered as **Rithy**. Change it with /owner NEW_NAME` | same |
| 12 | `/whoami` | `**Assistant**: userx AI` | same |
| 13 | `/tool` | `Usage: /tool TOOL_NAME` | same |
| 14 | `/research` | `Usage: /research QUERY` | same |
| 15 | `/task` | `Usage: /task DESCRIPTION` | same |
| 16 | `/model` (main) / `/model local` (branch) | `` `/model` lives in **Settings > AI** now. It keeps working here for this release. `` | same first line; second line `Switched to local model: **gemma4-e4b**` vs main's `Remote model set to ****` (the bug above) |
| 17 | `/prompt` | `The current system prompt is` | same |
| 18 | `/endpoint` | `` `/endpoint` lives in **Settings > AI** now. It keeps working here for this release. `` | same (second line shows the endpoint that was current at the time) |
| 19 | `/temp` | `Temperature: 0.8` | same |
| 20 | `/test` | `<think>` (the fixture from `testMessage.js`; rendered think block, table, code block and LaTeX are in `/tmp/j08-HV0yEy/shot-attach.png`) | same |
| 21 | `/attach` | typed without Enter: palette shows `/attach path` under "This conversation" with its description; field cleared (`shot-attach.png`) | — |
| 22 | `/key` | typed without Enter: palette shows `/key text` under "Settings — now in Settings > AI"; field cleared (`shot-key.png`) | — |

Raw first lines, both runs, in order (identical except rows 16 and 18 as noted):

```
$ jq -r '.messages[] | "\(.role)|\((.rawContent // .content) | tostring | split("\n") | map(select(length>0)) | .[0] // "" | .[0:110])"' ~/.local/state/quickshell/user/ai/chats/j08-main.json | cat -n
     1 interface|Usage: /save CHAT_NAME
     2 interface|Usage: /load CHAT_NAME
     3 interface|Not enough messages to fork.
     4 interface|Usage: /resume SESSION_ID
     5 interface|**This conversation**
     6 interface|Usage: /remember SOMETHING TO REMEMBER
     7 interface|**Stored memories** (forget with /forget ID):
     8 interface|Usage: /forget MEMORY_ID
     9 interface|You're registered as **Rithy**. Change it with /owner NEW_NAME
    10 interface|**Assistant**: userx AI
    11 interface|Usage: /tool TOOL_NAME
    12 interface|Usage: /research QUERY
    13 interface|Usage: /task DESCRIPTION
    14 interface|`/model` lives in **Settings > AI** now. It keeps working here for this release.
    15 interface|Remote model set to ****
    16 interface|The current system prompt is
    17 interface|`/endpoint` lives in **Settings > AI** now. It keeps working here for this release.
    18 interface|Remote endpoint: **https://api.openai.com/v1/chat/completions**
    19 interface|Temperature: 0.8
    20 interface|<think>
$ … j08-new.json …
    14 interface|`/model` lives in **Settings > AI** now. It keeps working here for this release.
    15 interface|Switched to local model: **gemma4-e4b**
    16 interface|The current system prompt is
    17 interface|`/endpoint` lives in **Settings > AI** now. It keeps working here for this release.
    18 interface|Remote endpoint: **http://127.0.0.1:9998/v1/chat/completions**
    19 interface|Temperature: 0.8
    20 interface|<think>
```
(rows 1–13 of the second run are byte-identical to the first and are not repeated.)

## Acceptance 3 — live behaviours, with `qs log` excerpts

None of these paths log anything on main or on this branch, so for the demo the live copy carried nine temporary `console.log("[J08] …")` lines in `AiChat.qml`'s signal handlers (plus two read-only demo properties on the transcript and two logs in `RecallStrip`'s recall callback).
Those copies are in `/tmp/j08-HV0yEy/instr/`; the committed files have none of it, and the final deploy (15:27:19) put the committed files live: `diff -rq ~/.config/quickshell/koompi/modules/koompi/sidebarLeft <repo>/…/sidebarLeft` → identical, `grep -c J08` → 0 in all three.

Deploy sequence: first copy 15:14:00 → `Reloading configuration… / Configuration Loaded` (log lines 151–156), final copy 15:27:19 → same (lines 246–251); `qs list` shows PID 702039 throughout.
No line from any of the eight files appears in the log at any point (`grep -E "AiChat.qml|ChatComposer|ChatTranscript|ChatCommands|CommandCompletion|RecallStrip|ContextMeter|testMessage"` minus the `[J08]` demo lines → empty).

```
# typing "/" shows the palette (22 entries, all commands, debugCommands is on in this config)
 DEBUG qml: [J08] palette after typing '/': entries=22 suggestionsVisible=true

# Tab from the composer focuses the transcript; Escape in the transcript hands focus back
 DEBUG qml: [J08] Tab from composer: transcript.focusTranscript() = true, transcript has focus = true
 DEBUG qml: [J08] transcript Esc/Backtab -> composer.focusInput()

# PageUp, PageUp, PageDown from the composer (the loaded conversation only has 62 px of scroll range)
 DEBUG qml: [J08] composer up: transcript.contentY 62 -> 0
 DEBUG qml: [J08] composer up: transcript.contentY 0 -> 0
 DEBUG qml: [J08] composer down: transcript.contentY 0 -> 62

# recall strip while typing a memory-matching phrase (memory #68/#69 are about the capital of Cambodia)
 DEBUG qml: [J08] recall strip: asking MemoryService.recall for "of Cambodia"
 DEBUG qml: [J08] recall strip: results=3 error="" dismissed=false
 DEBUG qml: [J08] recall strip shown = true, results = 3, typed = "of Cambodia"

# starter chip: after /clear, a ydotool click on "What can you do on this computer?" (screen 477,2053)
 DEBUG qml: [J08] starter chip chosen: "What can you do on this computer?"

# stall watchdog: the chip's message went to a blackhole endpoint (below); 60 s later the banner state flips,
# and the requester's own 180 s deadline clears it again
 DEBUG qml: [J08] transcript.stallDetected = true (Ai.requestActive=true)      # 15:24:28, click was 15:23:28
 DEBUG qml: [AI] request exceeded its 180s deadline, killing curl
 DEBUG qml: [J08] transcript.stallDetected = false (Ai.requestActive=true)
 DEBUG qml: [AI] curl exited 15 after the deadline, slot released
```

How the stall was forced: a Python socket server on `127.0.0.1:9377` that accepts and never replies (`/tmp/j08-HV0yEy/blackhole.log`: `accepted ('127.0.0.1', 41770) 15:23:28`), and `ai.localEndpoint` in `~/.local/state/quickshell/states.json` pointed at it through the file (Persistent's FileView has `watchChanges: true`), because typing `/endpoint local …` while Rithy was typing in a terminal was not safe.
The endpoint was set back to `http://127.0.0.1:9379/v1/chat/completions` at 15:26 and verified; the listener is stopped.
The banner itself was not screenshotted: by the time I took the shot the sidebar had been dismissed by Rithy's window, so `shot-stall.png` shows Chrome, and I did not want to pop the sidebar over a form being filled in.
The "inserts its text" wording for the chip: on main and here the chip clears the field and submits its text as the user message (`handleInput` did that; now `composer.submit`), which is what the log line and the blackhole's accepted connection show.

## Acceptance 4 — `qs log -c koompi | grep -iE 'AiChat|aiChat|error|undefined' | tail -30`

Full output at the end of the session (278 log lines, instance 3p1fx3abkt):

```
      WARN scene: @modules/koompi/sidebarLeft/aiChat/MessageCodeBlock.qml[242:-1]: TypeError: Cannot read property 'thinking' of undefined
      WARN scene: @modules/common/functions/StringUtils.qml[92:-1]: TypeError: Cannot read property 'length' of undefined
      WARN scene: @modules/koompi/sidebarLeft/aiChat/AiMessage.qml[153:9]: Unable to assign [undefined] to QObject*
      WARN scene: @modules/koompi/sidebarLeft/aiChat/AiMessage.qml[321:25]: Unable to assign [undefined] to bool
      … (the same three AiMessage/StringUtils lines ×8, MessageCodeBlock once more) …
     ERROR qml: [MemoryService:memd] memd: T0 fired after 46.1s idle: marked=1 extracted=0 stored=0 decayed=0 in 6.117897ms
```

Versus main: the baseline capture (`/tmp/j08-HV0yEy/qslog-main.txt`, 95 lines, before anything was typed) has only `SearchItem.qml[216]` ×4, `PlayerControl.qml` ×3 and a J20 debug line.
The `AiMessage.qml[321:25]`, `AiMessage.qml[153:9]`, `StringUtils.qml[92]`, `MessageCodeBlock.qml[242]` warnings are emitted per rendered message by `AiMessage.qml` (out of scope, unchanged) and first appear at log line 100, while main's code was still live and I was running the 22 commands on it: 19 of them before the first deploy at line 151, 35 after (two more command runs plus the demos).
The memd `ERROR` line belongs to the memory daemon.
No line names any of the eight files.

## Acceptance 5 — `./tests/run.sh` tail

Run twice: on the pre-rebase base (`/tmp/j08-HV0yEy/tests-after.txt`) and again after the rebase onto `c4d3c41b` (`tests-final.txt`, below), both with the allow-list row removed:

```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit=0
```

Same count as the lead's baseline on `86c616f5`.

## Rithy's live AI state: before vs after, and how it was checked

Before typing anything I had read the `ai` object of `~/.local/state/quickshell/states.json` (key fields excluded) and the thread index; at the end I diffed the same reads:

```
$ diff <(jq -S . ai-state-before.json) <(jq -S . ai-state-after.json)
8c8
<   "remoteModel": "gemini-flash-latest",
---
>   "remoteModel": "0xAlpha",
$ jq -r .current ~/.local/state/quickshell/user/ai/chats/index.json; jq -r .current chats-backup/index.json
lastSession
lastSession
$ cmp ~/.local/state/quickshell/user/ai/chats/lastSession.json chats-backup/lastSession.json && echo identical
identical
```

So `ai.model` (`local`), `ai.localModel`, `ai.localEndpoint`, `ai.remoteEndpoint`, `ai.remoteFormat`, `ai.temperature`, `ai.ownerName`, the `current` thread pointer and the conversation file are exactly as before.
The one difference, `remoteModel: 0xAlpha`, is not mine: my restore of that key (to `gemini-flash-latest`, 15:12) predates it, and LEAD.md records "15:20 Rithy: remote AI = 0xAlpha".
I left it, because reverting it would undo Rithy's own change.

## Live-desktop side effects left behind

- Rithy's conversation: `lastSession.json` (09:12, 11532 bytes) was never rewritten; `index.json`'s `current` pointer, which `/save` had moved to my thread, was set back to `lastSession` before the final reload, and `Ai.loadChat("lastSession")` restored it at startup.
- Three thread files and index rows were added by the `/save`s: `j08-probe.json`, `j08-main.json`, `j08-new.json`.
  Left in place rather than deleting from a live state directory; `/load` ignores them, and `chats-backup/` in the temp dir has the pre-run directory.
- `states.json` keys touched and restored: `ai.model`, `ai.remoteModel`, `ai.remoteEndpoint` (by the `/model` bug), `ai.localEndpoint` (by the stall demo).
  `ai.remoteModel` later read `0xAlpha`; that change came from elsewhere at 15:20 (the J27 work), not from this job.
- The lead's herdr pane and Rithy's Chrome window received the stray keys described at the top.
