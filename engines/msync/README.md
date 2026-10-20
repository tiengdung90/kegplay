# msync for Wine 11 on macOS

A patch that adds **msync** to upstream Wine 11.18 on macOS. msync is the Mach-semaphore synchronization backend that CrossOver uses. With it, Windows events, mutexes and semaphores are handled inside each process. Without it, every wait and wake goes through `wineserver`.

Free Wine builds for macOS, such as [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds), ship without msync. The original [wine-msync](https://github.com/marzent/wine-msync) patches target Wine 9.x and do not apply to Wine 11, which reworked its synchronization code around `inproc_sync` (the framework NTSYNC uses on Linux). CrossOver 26 plugs msync into that framework, and this patch carries that design over to Wine 11.18.

kegPlay ships this in its DXMT engine. The patch does not depend on kegPlay and works on a plain Wine build.

## Results

Measured on an M2 Pro with `tools/diag/syncbench.c` (a small Windows program; it also checks that results are correct). Unmodified Gcenx Wine 11.18 runtime, with `ntdll.so` and `wineserver` built from this patch:

| Test | `WINEMSYNC=0` | `WINEMSYNC=1` |
|---|---|---|
| Two threads waking each other through auto-reset events | 42,648 round trips/s | 153,411 (×3.6) |
| Four threads contending for one mutex | 97,045 acquisitions/s | 1,060,868 (×10.9) |
| Semaphore producer/consumer | 87,177 operations/s | 808,730 (×9.3) |

All four correctness checks pass in both modes. Run with `WINEMSYNC=0`, the patched build performs the same as the stock Gcenx binaries (43,355 / 99,087 / 88,747 in the same test), so the gain comes from msync itself and not from how it was built.

In a real game (Mount & Blade II: Bannerlord, DXMT), `wineserver` dropped from about 16% to about 4% of one core, and the tester reported less stutter in dialogue and loading. Frame rates were not measured.

## Use

```bash
cd wine-11.18                      # upstream source: https://dl.winehq.org/wine/source/11.x/wine-11.18.tar.xz
patch -p1 < wine-11.18-msync.patch
./configure --enable-archs=x86_64 ...   # your usual options
make server/wineserver dlls/ntdll/ntdll.so
```

Copy the new `server/wineserver` into your Wine's `bin/` and `dlls/ntdll/ntdll.so` into `lib/wine/x86_64-unix/`, then ad-hoc sign them (`codesign -f -s - <file>`). Run with `WINEMSYNC=1`. Wine prints `msync: up and running.` when it is active.

- **Always replace both files together.** The patch adds a field to the server protocol (`SERVER_PROTOCOL_VERSION` 962 → 963), so a mismatched `ntdll.so`/`wineserver` pair will not start.
- **Stop Wine before switching** (`wineserver -k`). Every process in a prefix must agree on `WINEMSYNC`; if they do not, Wine reports "Server is running with WINEMSYNC but this process is not".
- macOS only. On Linux, Wine 11 has NTSYNC.

## How it is made

| File | What |
|---|---|
| `src/` | The five msync source files, unchanged from the CrossOver 26.3.0 source release (`crossover-sources-26.3.0.tar.gz`, sha256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`). Only the msync block of `inproc_sync.c` is used. |
| `port-msync.py` | Wires msync into Wine 11.18's `inproc_sync` code at about ten points, and stops if any point no longer matches. |
| `patches/wine-11.18-msync.patch` | The resulting diff against upstream Wine 11.18, including the regenerated protocol files. |
| `build-msync.sh` | kegPlay's build of `ntdll.so` + `wineserver` (`lib/`). |

To regenerate the patch for a newer Wine, run `port-msync.py` on that source tree, then `perl tools/make_requests`, and diff the result. If upstream has moved code around, `port-msync.py` reports which point failed instead of producing a broken tree.

## Credits and license

msync was written by **Marc-Aurel Zent** (CodeWeavers), building on esync and fsync by **Zebediah Figura**. CodeWeavers integrated it with `inproc_sync` in CrossOver. kegPlay only adapted that work to upstream Wine 11.18 and tested it. Everything here is under the **LGPL 2.1 or later**, like Wine.

Bugs in this port are kegPlay's, not CodeWeavers'. Please report them at https://github.com/tiengdung90/kegplay/issues.
