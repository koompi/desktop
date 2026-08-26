# Desks

Instead of piling every window onto one screen, you get ten separate desks.
Put your writing on one and your browser on another.
Nothing on the desk you are not looking at can interrupt what is in front of you.

There is no setting up to do.
A desk exists when you put something on it and stops existing when you take it away.

## Moving between them

| Keys | Goes to |
| --- | --- |
| `Super+1` to `Super+0` | that desk, by number |
| `Ctrl+Super+Left` and `Ctrl+Super+Right` | the desk to either side |
| `Super+PageUp` and `Super+PageDown` | the same, on a keyboard with those keys |

On a touchpad, four fingers left or right walks between desks.
Scrolling the wheel over the numbers at the top of the screen does the same.

The numbers themselves are in the middle of the top strip.
A desk with something on it is filled in; an empty one is not.

## Sending a window somewhere else

`Super+Alt+1` to `Super+Alt+0` sends the window you are in to that desk and leaves you where you are.
`Super+Shift+PageUp` and `Super+Shift+PageDown` send it one desk over.

You can also throw it by hand.
Press `Super+Tab` for the overview, then drag any window onto any desk.

## Seeing all of it at once

`Super+Tab` lays every window on every desk out small, in one picture.
Four fingers up or down does the same.

Click a window to go to it.
Drag a window onto another desk to move it there.
Press `Super+Tab` again, or Escape, to leave.

This is what you reach for when you have lost something.

## The scratchpad

One more desk sits outside the ten, hidden until you ask for it.

`Super+S` shows it and hides it again.
`Super+Alt+S` sends the window you are in there.

Use it for the thing you keep coming back to and do not want in the way: a chat window, a notepad, a running log.

## A wallpaper for each desk

Each desk can carry its own picture, and the desktop recolours itself around whichever one you are on.

```sh
koompi wallpaper status              # what each desk is set to now
koompi wallpaper set 3 ~/Pictures/river.jpg
koompi wallpaper seed                # give all ten a different random one
```

`Ctrl+Super+T` opens the picker for the desk you are on.
`Ctrl+Super+Alt+T` rolls a random one for that desk and nothing else.
