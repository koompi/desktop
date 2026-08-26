# Settings, and getting help

## Settings

`Super+I` opens KOOMPI Settings.
`Super+I` again closes it.

The pages are Quick, General, Bar, Background, Interface, Displays, Input, Shortcuts, Network, Bluetooth, Sound, Power, Privacy, Account, AI, Services, Advanced and About.

Go straight to one from a terminal:

```sh
koompi settings bluetooth
koompi settings power
```

## The list of every shortcut

`Super+/`.

It is built from the shortcuts themselves rather than written by hand, so it cannot drift out of date the way this manual can.
When the two disagree, believe `Super+/`.

## The tour

`Super+Shift+/` walks you through the desktop and opens each part as it names it.
It takes a few minutes and you can leave whenever you like.

If you have just installed KOOMPI, start there and come back here afterwards.

## Your own shortcuts

Your keybinds live in a file of your own that an update never overwrites:

```
~/.config/hypr/custom/keybinds.lua
```

`Ctrl+Super+Alt+/` opens it.

## When the desktop misbehaves

```sh
koompi doctor
```

reports what is running, what is installed and what is missing, and changes nothing.

`Ctrl+Super+R` restarts the shell without touching your windows.
`koompi reload` reloads the whole configuration and restarts the shell.

## Language

`Super+Space` switches the keyboard between English and Khmer.
Which one is live is shown in the top strip.

`Super+K` puts a keyboard on the screen, for a tablet or a laptop with a broken key.

## Ending the day

| Keys | Does |
| --- | --- |
| `Super+L` | lock the screen |
| `Super+Shift+L` | sleep |
| `Ctrl+Alt+Delete` | the session menu: lock, sleep, log out, task manager, shut down, restart |
| `Ctrl+Shift+Alt+Super+Delete` | shut down, no menu, no question |

Closing the lid locks the screen unless an external monitor is attached.
