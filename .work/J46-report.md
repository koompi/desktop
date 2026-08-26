# J46 report — kernel sysctl defaults for the zram machine (J14 finding d)

Branch `j46-sysctl-defaults`, commit `301530e7`.
Files touched: `sdata/dist-arch/koompi-sysdefaults/files/usr/lib/sysctl.d/90-koompi.conf` (new),
`tests/test_sysdefaults.sh` (extended). Nothing else.

## Premise check (stop condition 1)

Read `sdata/dist-arch/koompi-sysdefaults/files/usr/lib/systemd/zram-generator.conf.d/90-koompi.conf`
first: `[zram0]`, `zram-size = ram`, `compression-algorithm = zstd`,
`swap-priority = 100` ("above the pri=0 a disk swapfile gets"). The premise holds — on a
KOOMPI install swap is compressed RAM sitting above any disk swap — so none of the reclaim
values invert. Proceeded.

## PKGBUILD: no change needed (stop condition 2 does not trigger)

The fan-out is `find "$_src" -type f -print0` over all of `files/`, so a new directory
(`files/usr/lib/sysctl.d/`) needs no install line and no special case. Verified by building:
the file appears in the artifact at the right path (acceptance 3). `pkgrel` left at 2,
`pkgver` and `depends` untouched.

## Acceptance 1 — the finished 90-koompi.conf, every key with its reason

```
$ cat sdata/dist-arch/koompi-sysdefaults/files/usr/lib/sysctl.d/90-koompi.conf
# Kernel defaults for the machine this package describes: a 4-8 GB laptop
# whose swap is the zram device from our zram-generator drop-in - compressed
# RAM at zstd's roughly 3:1, sitting at priority 100 above any disk swap -
# on school Wi-Fi. Reclaim lands in silicon before it touches storage, and
# the numbers below follow from that premise.
#
# Vendor drop-in under /usr/lib/sysctl.d/: an admin overrides any of this
# from /etc/sysctl.d/, which sorts after it and shadows the whole file by
# the same name.

# Evicting an anonymous page costs one zstd compression and, on fault-back,
# one decompression - both in RAM. Dropping a page-cache page instead costs
# a storage round-trip to get it back, so on this hardware the anonymous
# page is usually the cheaper victim and swappiness above 100 tells the
# kernel exactly that. Not 200: past a point every reclaim pays the
# compression tax for pages the cache could have kept.
vm.swappiness = 150

# The inode and dentry caches are kernel metadata; they never reach zram,
# and losing them turns pathname lookups back into storage I/O. Halve how
# eagerly they are reclaimed. Not lower: pressure 0 disables their reclaim
# outright, and 4 GB will OOM with the cache pinned before swap fills.
vm.vfs_cache_pressure = 50

# A swap-in fault reads back one page. The stock cluster of 8 exists to
# amortise a disk seek that zram does not have, and each extra page in the
# cluster is another decompression of data nothing asked for yet.
vm.page-cluster = 0

# After a fragmentation event the kernel briefly inflates its watermarks,
# and kswapd then reclaims while memory is still plentiful - a stutter the
# user feels and cannot explain. The high-order allocations boost exists
# to protect are a large-server concern, not a laptop's.
vm.watermark_boost_factor = 0

# Widen the watermark span to about 1.25% of RAM so kswapd wakes early and
# finishes its work in the background. At the stock 0.1% the span is tight
# enough that ordinary allocations fall through to direct reclaim, which
# stalls whatever task asked until reclaim completes.
vm.watermark_scale_factor = 125

# Dirty limits as fractions of RAM let hundreds of megabytes queue before
# writeback stirs, then flush in one long stall. Pin the bounds in bytes,
# neither of which scales up with a bigger RAM stick than ours.
# Background writeback starts here:
vm.dirty_background_bytes = 67108864
# Writers hard-throttle here - past this line, dirtiers sleep until it drains:
vm.dirty_bytes = 268435456

# With the burst bounded above, waking the flusher every 15 s instead of
# 5 s loses nothing and buys back two wakeups per dirty interval.
vm.dirty_writeback_centisecs = 1500

# One node_modules tree exhausts the stock 8192 watches and the editor
# fails with ENOSPC on inotify, which reads like a dying disk. The limit
# caps watches; it reserves nothing until an application actually asks.
fs.inotify.max_user_watches = 524288

# Campus NAT and captive portals routinely swallow the ICMP that path-MTU
# discovery depends on, wedging sessions mid-transfer below the real MTU.
# Probing recovers them instead of waiting for a clamp message that never
# comes; SSH surviving the school network is worth one probe.
net.ipv4.tcp_mtu_probing = 1
```

## Acceptance 2 — test run, rc 0, new assertions included

```
$ nice -n 19 ionice -c 3 bash tests/test_sysdefaults.sh; echo "rc=$?"
built koompi-sysdefaults-1.0-2-any.pkg.tar.zst
ok test_sysdefaults.sh
rc=0
```

New assertions in `tests/test_sysdefaults.sh`:

- ten whole-line `expect`s pinning each key/value;
- §1b: extracts every key the file sets (`grep -Ev '^(#|$)' | sed 's/[[:space:]=].*//'`) and
  requires `sysctl -n <key>` to read it on this kernel — reads only, never writes;
- §1c: walks the file line by line and requires the line above every setting to be a comment;
- §4: `pacman -Qlp "$pkg"` must list `koompi-sysdefaults /usr/lib/sysctl.d/90-koompi.conf`
  (captured first, not piped into `grep -q`, same SIGPIPE reasoning as the existing depends
  checks), and the tar-listing diff now expects eight `/usr/lib` files + the ufw profile.

Both new source assertions were probed negative before trusting them (file restored after):

```
$ sed -i '/swap-in fault reads back one page/,+2d' .../sysctl.d/90-koompi.conf && bash tests/test_sysdefaults.sh
FAIL: sysctl.d/90-koompi.conf sets 'vm.page-cluster = 0' with no comment above it

$ printf '# probe\nvm.bogus_probe_key = 1\n' >> .../sysctl.d/90-koompi.conf && bash tests/test_sysdefaults.sh
FAIL: this kernel does not know 'vm.bogus_probe_key' from sysctl.d/90-koompi.conf
```

## Acceptance 3 — pacman -Qlp on the built package

```
$ pacman -Qlp koompi-sysdefaults-1.0-2-any.pkg.tar.zst | grep sysctl.d
koompi-sysdefaults /usr/lib/sysctl.d/
koompi-sysdefaults /usr/lib/sysctl.d/90-koompi.conf
rc=0
```

(Built with the test's flags: `BUILDDIR=... PKGDEST=... SRCDEST=... makepkg --force --cleanbuild --nodeps`.)

## Acceptance 4 — shellcheck

```
$ shellcheck tests/test_sysdefaults.sh && shellcheck -x tests/test_sysdefaults.sh && echo clean
shellcheck clean
```

(No output from either invocation; the `&&` chain reached the echo.)

## Acceptance 5 — decision table, all ten candidates

Values equal omarchy's where omarchy sets the key: our premise (zram at `zram-size = ram`,
zstd) is identical to theirs, so their numbers transfer. Prose is ours throughout.

| key | take/drop | value | reason |
|---|---|---|---|
| `vm.swappiness` | take | 150 | anon evicts to compressed RAM cheaper than a page-cache page re-reads from storage; not 200, each swap fault pays compress/decompress |
| `vm.vfs_cache_pressure` | take | 50 | dentry/inode cache never reaches zram; dropping it means storage I/O to rebuild; not lower, pressure 0 OOMs a 4 GB box |
| `vm.page-cluster` | take | 0 | no seek to amortise on zram; each extra clustered page is an unneeded decompression |
| `vm.watermark_boost_factor` | take | 0 | post-fragmentation watermark inflation makes kswapd reclaim while memory is free; protects high-order allocs a laptop doesn't make |
| `vm.watermark_scale_factor` | take | 125 | widens the watermark span to ~1.25% so kswapd works in background instead of allocations falling into direct-reclaim stalls |
| `vm.dirty_background_bytes` | take | 67108864 | percent-based defaults queue hundreds of MB then flush in one stall; fixed 64 MiB start-of-writeback bound |
| `vm.dirty_bytes` | take | 268435456 | hard throttle at 256 MiB so dirty bursts stay bounded regardless of RAM size |
| `vm.dirty_writeback_centisecs` | take | 1500 | bursts bounded above, so 15 s flusher wakeups lose nothing and save two wakeups per interval |
| `fs.inotify.max_user_watches` | take | 524288 | stock 8192 dies on one node_modules tree with ENOSPC that reads like disk failure; cap reserves nothing until used |
| `net.ipv4.tcp_mtu_probing` | take | 1 | school Wi-Fi/captive portals drop PMTUD ICMP and wedge sessions; probing recovers them |

Note for the lead: the job brief said omarchy's `99-omarchy-sysctl.conf` carries the inotify
key; as checked out it does not — omarchy ships it separately in
`~/.tmp/omarchy/etc/sysctl.d/90-omarchy-file-watchers.conf` (same 524288). Decided on our own
grounds either way; dev tools hitting ENOSPC is a KOOMPI-laptop failure mode.

## Scope compliance

No live state touched: no `sysctl -w`, no `--system`, no writes under `/etc`; the kernel-known
check uses `sysctl -n` (read-only); makepkg/pacman operate on temp dirs and package files only.
zram/oomd/shutdown drop-ins untouched; `pkgrel` untouched; no push.
