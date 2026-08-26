# Getting online

## Wi-Fi

Press `Super+N` for the right-hand panel.
The tile marked **Internet** shows the network you are on.

Click the tile to turn Wi-Fi off and on.
Right-click it and the list of networks in range appears.
Pick one, type the password if it wants one, and you are on.

The same list lives in Settings under Network, along with a rescan button and the state of your wired connection.
`Super+I`, then Network.

## Bluetooth

The tile beside it is Bluetooth, and it behaves the same way.
Click to turn the radio on and off, right-click for the list of devices to pair with.

## Browsing

`Super+W` opens your browser.

To search the web without opening it first, tap Super and put `?` in front of what you want.
Enter hands the search to the browser.

## Making a website into a program

A site you use every day does not have to live in a browser tab.

```sh
koompi webapp install "Khan Academy" https://khanacademy.org
```

It gets its own window, its own icon, and its own entry in Search, with no tabs and no address bar around it.

```sh
koompi webapp remove "Khan Academy"
```

removes it again.

When no icon can be found on the site itself, the installer asks a third-party service for one, which means the site's address leaves your machine.
Pass an icon yourself as the third argument and nothing is sent anywhere.
