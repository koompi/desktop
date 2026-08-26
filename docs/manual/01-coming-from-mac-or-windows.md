# Coming from Mac or Windows

You already know how to use a computer.
This chapter is only about the handful of things KOOMPI does differently.
Once these are in your hands, the rest of the manual is ordinary.

## The Super key

The key between Ctrl and Alt, the one printed with a Windows logo or a Command symbol, is called **Super** here.
It is the one key you have to learn.

Tap it on its own and let go, and Search opens.
Hold it and press another key, and you have given a command.

`Super+/` puts every shortcut on the screen.
`Super+Shift+/` starts the guided tour, which opens each part of the desktop as it names it.
You are not expected to remember any of this from reading.

## Where the taskbar and the dock went

There is neither.
There is a strip along the top of the screen, and it never moves.

On the left is the KOOMPI star and the name of the program you are in.
In the middle are your desks.
On the right are the clock, sound, network, battery, and anything asking for your attention.

You do not click along a taskbar to change programs.
You tap Super and type the name, or press `Super+Tab` and see every window at once.

A dock exists and it ships switched off.
Settings has the switch if you want one back.

## Windows arrange themselves

Nothing overlaps by default.
Open one window and it fills the screen.
Open a second and the screen splits between the two.
Open a third and it takes its share of the split.

You do not drag windows into position.
`Super+Left` and `Super+Right` move your attention between them.
`Super+Shift+Left` and `Super+Shift+Right` move the window itself.

When you want one window loose, `Super+Alt+Space` sets it free to float.
When you want the whole desktop to behave the way Windows does, `Super+Shift+Space` switches every window to stacking and back.

## What replaced Finder and Explorer

`Super+E` opens the file manager.
On a full KOOMPI install that is Dolphin.

For finding rather than browsing, tap Super and put `~` in front of what you type.
That searches your files and nothing else.

## Where the settings live

`Super+I` opens KOOMPI Settings, and `Super+I` again closes it.
Sound, network, Bluetooth, displays, power, the bar, the sidebars and the assistant are all in there.

The desktop takes its colours from your wallpaper.
`Ctrl+Super+T` picks a new one.
`Ctrl+Super+Shift+D` swaps light for dark.

## Installing software

KOOMPI ships no software shop.
Programs come from your distribution's package manager, in a terminal, the same as on any Linux machine.

A website can become a program of its own:

```sh
koompi webapp install "HEY" https://hey.com
```

It gets an icon, an entry in Search, and a window with no browser wrapped around it.
`koompi webapp remove HEY` takes it away again.

## What closing the lid does

It locks the screen.
It does not lock when an external monitor is attached, so a docked laptop keeps working with the lid down.

Left alone, the machine shows a screensaver after two minutes, locks after five, turns the screen off after ten, and sleeps after fifteen.
The **Keep awake** tile in the right-hand panel stops all four while it is on.

## Two habits to unlearn

`Alt+F4` does not close a window here.
`Super+Q` does, and pressing `Alt+F4` tells you so instead of ignoring you.

`Ctrl+Alt+Delete` is not a rescue key.
It opens the session menu: lock, sleep, log out, task manager, shut down, restart.
