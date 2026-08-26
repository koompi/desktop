# Updates, and going back

## Updating

```sh
koompi update
```

That is the whole thing.
There are two ways a KOOMPI desktop can be installed, and the command works out which one you have and does the right thing for it.

When updates are waiting, a count appears in the top strip.
Click it and the same command runs in a terminal window.
Middle-click it to check again.

Useful flags:

```sh
koompi update --dry-run     # say what would happen, change nothing
koompi update --yes         # ask nothing
koompi update --no-reload   # leave the running session alone until next login
koompi update --firmware    # firmware only, nothing else
```

An update needs 2 GiB free and refuses to run twice at once.
It keeps the machine awake while it works, and it will not restart the shell out from under a locked session.

Every real run writes a transcript, kept on your machine and never uploaded:

```sh
koompi doctor --last-update
```

## Your settings survive it

Your `config.json` is written once, at first run, and never touched again.
That means a better default shipped later would never reach you, so each update merges the changed defaults into your file and backs the old one up as `config.json.bak-<timestamp>` first.

Your own choices win every time there is a disagreement.

## Snapshots

On a KOOMPI OS install, the disk is btrfs and the system can be photographed before it changes.

```sh
koompi snapshot create --description "before I try this"
koompi snapshot list
koompi snapshot rollback 42
```

A packaged update takes one of these on its own, before it upgrades anything.

`rollback` does not reboot for you.
It prints the remaining steps and leaves them to you, because rolling a running system back under itself is not something to do by surprise.

On a machine that is not btrfs, or was installed from a git checkout, every one of these commands says so and exits without doing anything.
Nothing breaks; there is simply nothing to snapshot.

## When something is wrong

```sh
koompi doctor
```

It checks the compositor, the shell, the portals and the supporting tools, and prints what is present, what is running and what is missing.
It changes nothing.
