# Files

## Browsing

`Super+E` opens the file manager.
A full KOOMPI install gives you Dolphin; on a machine without it, the key falls through to whichever one is there.

## Finding

Tap Super, type `~`, then part of the name.
Search looks through your files and shows nothing else.
Enter opens the one you picked in whatever program owns that kind of file.

## Looking without opening

Quick Look shows you what is in a file without launching anything.

```sh
koompi preview ~/Documents/contract.pdf
```

It knows images, video, audio, PDFs and anything that is really text.
The same command again closes it, and so do Space and Escape inside the preview.

Wire it into Dolphin once:

```sh
koompi preview install
```

After that, select a file in Dolphin and press Space.
That is the same gesture macOS gives you, and it is off until you ask for it.

## Sending a file to Google Drive

```sh
koompi preview drive ~/Documents/report.pdf
```

With `rclone` set up against a Drive remote, the file is uploaded for you.
Without one, the file goes onto your clipboard so you can paste it in yourself.
Either way, Drive opens in your browser.

## Signing a document

You need your signature once, as an image with nothing behind it.

```sh
koompi signature capture           # hold the paper up to the camera
koompi signature from ~/Pictures/sig.jpg   # or use a photo you already took
koompi signature list
```

`Super+Shift+E` runs the camera capture directly.

To put it on the toolbar of the PDF reader:

```sh
koompi signature install-okular
```
