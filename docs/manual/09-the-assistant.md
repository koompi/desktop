# The assistant

## Where it is

`Super+A` opens the left-hand panel, or click the KOOMPI star at the top left.
`Super+A` again puts it away.

`Super+Shift+I` opens the same assistant as a full window when the panel is too narrow for what you are doing.
`Super+Alt+A` pulls the panel off the edge so it floats.

Type a question and press Enter.
The conversation you were in reopens the next time you log in.

## Slash commands

Anything starting with `/` is an instruction to the assistant itself, not a question for it.

| Command | Does |
| --- | --- |
| `/help` | list all of them |
| `/model` | show or change which model answers |
| `/key` | store the key a model needs |
| `/clear` | start a fresh conversation |
| `/save` and `/load` | keep a conversation and bring it back |
| `/attach` | send it a file |
| `/remember` and `/forget` | keep something across conversations, or drop it |
| `/memories` | see what it has kept |

Most models want an API key before they will answer.
The assistant tells you which one it needs and where to get it, and `/key` is where you put it.

## What it remembers

The assistant keeps notes across conversations and pulls in the relevant ones before it answers.
`/memories` lists them.
`/forget` removes one.

Turn the whole thing off in Settings under AI if you would rather it kept nothing.

## Talking instead of typing

Dictation needs the `koompi-kiri` package and a voice model on disk.
The models are hundreds of megabytes, so nothing is downloaded until you ask:

```sh
kiri model download silero-vad     # required by every backend
kiri model download parakeet       # English
```

Then the AI key on the keyboard, or `Super+Shift+K` for Khmer, starts listening.
A red microphone appears in the top strip while it is.
`Super+Escape` cancels.

## The translator

The panel can carry a translator beside the assistant.
It ships turned off; the switch is in Settings, under Interface, with the sidebars.

## Agents in a terminal

```sh
koompi workbench
```

opens a persistent workspace for the coding agents, in a terminal, in your projects folder.
It needs Herdr installed; `./setup install --only-apps` puts it there.

While an agent is running, what it has used shows in the top strip, and `Super+Ctrl+1` opens the detail.
