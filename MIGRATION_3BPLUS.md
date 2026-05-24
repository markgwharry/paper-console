# PC-1 Migration: Pi 5 (1GB) → Pi 3B+

Plan for moving an already-provisioned PC-1 install off a Raspberry Pi 5 (1GB) onto a spare Raspberry Pi 3B+, so the Pi 5 can be reprovisioned for other use. For canonical wiring see `HARDWARE_BUILD.md`; only the deltas are documented here.

> Target state after migration: same hostname (`pc-1`), same Tailscale node identity, same device password, same `config.json`, same printer wiring. Only the SoC and the two config.txt lines that depend on it change.

---

## 1. Why this is straightforward

- **40-pin GPIO header is electrically identical** between Pi 5 and Pi 3B+. Every BCM GPIO lands on the same physical pin number. The dupont housings A1, A2, B, C1, C2 plug onto the 3B+ unchanged. See §6 for the side-by-side table.
- **Pi OS Trixie image is already cross-board**. `dpkg -l` on this device shows both `linux-image-rpi-2712` (Pi 5) and `linux-image-rpi-v8` (Pi 3/4/Zero 2) installed, and `/boot/firmware` contains `bcm2710-rpi-3-b-plus.dtb` + `kernel8.img`. The firmware will pick the right kernel/dtb at boot based on SoC detection.
- **Tailscale state lives on disk**. Moving the SD card preserves `/var/lib/tailscale/tailscaled.state`, so the node keeps its IP (`100.89.148.77`) without re-auth.
- **App is hardware-agnostic above the driver layer**. `app/drivers/gpio_ioctl.py` talks to `/dev/gpiochip0` via kernel ioctl — Pi 5 RP1 and Pi 3B+ BCM2837 both expose that path. Pyserial talks to `/dev/serial0`, which the udev rule + the config.txt edit below guarantee points to PL011 on GPIO 14/15.

What does change:
1. **UART mapping**. On Pi 3B+, PL011 (`ttyAMA0`) is wired to the Bluetooth modem by default. The `dtoverlay=disable-bt` overlay redirects it to GPIO 14/15 where the printer is.
2. **`dtparam=uart0=on`** is BCM2712 syntax. The 3B+ uses `enable_uart=1` instead.
3. **Power connector**. Pi 3B+ takes micro-USB at 5V/2.5A, not USB-C. Confirm PSU before swap.

---

## 2. Approach

Three options; pick **B**.

| | A. Move SD as-is | **B. Clone, then swap** | C. Fresh re-image |
|---|---|---|---|
| Downtime on Pi 5 | Until SD card returns | None | None |
| Rollback path | Re-image from scratch | Re-insert original SD into Pi 5 | Re-image from scratch |
| Pi 5 reusable | After re-imaging | Immediately | Immediately |
| Identity preserved (hostname, Tailscale, keys) | Yes | Yes | No — fresh provisioning |
| Risk | Single point of failure | Lowest | Re-runs `setup_pi.sh`, risk of the hostname-prompt mishap (CLAUDE.md §"When an LLM is doing the provisioning") |

Option B leaves you with a verified rollback artifact (the original SD card) and frees the Pi 5 immediately.

---

## 3. Pre-flight on the Pi 5

Run before powering down:

```bash
# Stop the app and storage guard cleanly.
sudo systemctl stop pc-1.service pc1-storage-guard.timer

# Confirm clean working tree (no uncommitted dev work on the device).
cd ~/paper-console && git status -sb

# Note current state for post-migration verification.
tailscale status | grep $(hostname)
cat /etc/os-release | grep VERSION_ID
df -h /
vcgencmd get_throttled    # baseline for comparison post-boot
```

If `git status` shows unstaged changes that matter, commit or stash them first — the migration assumes the working tree is the source of truth.

---

## 4. Clone the SD card

On a separate Linux/Mac host with a USB SD reader:

```bash
# Identify source card (the Pi 5's card)
lsblk
SRC=/dev/sdX        # adjust
DST=/dev/sdY        # the fresh ≥16 GB target card, A1/A2 class

# Clone (bs=4M is the usual sweet spot; conv=fsync forces a final sync)
sudo dd if=$SRC of=$DST bs=4M status=progress conv=fsync
sync
```

Alternatives that also work:
- Raspberry Pi Imager → **Tools → Backup** (image-to-file) then write the image back to the new card.
- `pv -tpreb $SRC | sudo dd of=$DST bs=4M` for a progress bar.

Don't shrink the image — 4.7 GB used on a 29 GB root works fine, and shrinking adds a failure mode you don't need.

---

## 5. Apply the config.txt edits

The clone boots with Pi-5-tuned UART settings that don't fit the 3B+. Edit `config.txt` on the **clone's boot partition** before first boot.

### Manual diff

```diff
 [cm5]
 dtoverlay=dwc2,dr_mode=host

+[pi5]
+dtparam=uart0=on
+
+[pi3+]
+enable_uart=1
+dtoverlay=disable-bt
+
 [all]
-dtparam=uart0=on
```

Line-by-line:
- Move `dtparam=uart0=on` from `[all]` into `[pi5]` — BCM2712-only syntax.
- `[pi3+]` filter matches BCM2837B0 (the 3B+ specifically).
- `enable_uart=1` pins the VPU core clock so the mini UART baud is stable. Insurance; we don't actually use the mini UART, but it costs nothing.
- `dtoverlay=disable-bt` is the load-bearing line: it moves PL011 off the Bluetooth modem and onto GPIO 14/15, where the printer's TX/RX/DTR are wired.

### Or use the script

```bash
# On the cloning host, with the boot partition mounted:
./prepare-for-3bplus.sh /mnt/clone-boot

# Or on the Pi 3B+ itself after first boot (idempotent, default path):
sudo ./prepare-for-3bplus.sh
```

The script lives at `scripts/prepare-for-3bplus.sh` in this repo. It backs up `config.txt` to `config.txt.pre-pi3bplus.<timestamp>` and is guarded by marker comments so re-runs are no-ops.

### Don't touch

- `/etc/udev/rules.d/99-pc1-serial0.rules` — the override stays. On the 3B+ it lines up with reality (ttyAMA0 = PL011 = printer pins), so it's harmless. On the Pi 5 it was load-bearing; we keep the file for round-trip parity if you ever swap the card back.
- `cmdline.txt` — no `console=serial0` entry, so the serial console isn't competing for the UART. Leave as-is.
- `[cm4]` / `[cm5]` blocks — inert on 3B+.

---

## 6. Pin compatibility table — Pi 5 ↔ Pi 3B+

Every position on the 40-pin header maps to the same BCM GPIO on both boards. The housings from `HARDWARE_BUILD.md` §4 plug onto the 3B+ in the same orientation.

```
                              Pi 5 (RP1)     Pi 3B+ (BCM2837)    Housing / role
Pin 1   3V3                     3V3            3V3                —
Pin 2   5V        ← A1 pos 1    5V             5V                 A1 +5V (red A)
Pin 3   GPIO2                   GPIO2          GPIO2              —
Pin 4   5V        ← A1 pos 2    5V             5V                 A1 +5V (red B)
Pin 5   GPIO3                   GPIO3          GPIO3              —
Pin 6   GND       ← A1 pos 3    GND            GND                A1 GND (black)
Pin 7   GPIO4                   GPIO4          GPIO4              —
Pin 8   GPIO14    ← A2 pos 1    UART0 TX*      UART0 TX (PL011)†  Printer RX   *
Pin 9   GND                     GND            GND                —
Pin 10  GPIO15    ← A2 pos 2    UART0 RX*      UART0 RX (PL011)†  Printer TX   *
Pin 11  GPIO17                  GPIO17         GPIO17             —
Pin 12  GPIO18    ← A2 pos 3    GPIO18         GPIO18             Printer DTR
Pin 13  GPIO27                  GPIO27         GPIO27             —
Pin 14  GND       ← A2 pos 4    GND            GND                Printer GND
Pin 15  GPIO22                  GPIO22         GPIO22             —
Pin 16  GPIO23                  GPIO23         GPIO23             —
Pin 17  3V3                     3V3            3V3                —
Pin 18  GPIO24                  GPIO24         GPIO24             —
Pin 19  GPIO10                  GPIO10         GPIO10             —
Pin 20  GND       ← B pos 1     GND            GND                Button GND
Pin 21  GPIO9                   GPIO9          GPIO9              B pos 2 unwired
Pin 22  GPIO25    ← B pos 3     GPIO25         GPIO25             Button signal
Pin 23  GPIO11                  GPIO11         GPIO11             —
Pin 24  GPIO8                   GPIO8          GPIO8              —
Pin 25  GND                     GND            GND                —
Pin 26  GPIO7                   GPIO7          GPIO7              —
Pin 27  GPIO0  (ID_SD)          GPIO0          GPIO0  (HAT EEPROM) leave alone
Pin 28  GPIO1  (ID_SC)          GPIO1          GPIO1  (HAT EEPROM) leave alone
Pin 29  GPIO5     ← C1 pos 1    GPIO5          GPIO5              Dial pos 1
Pin 30  GND       (C2 pos 1)    GND            GND                unwired
Pin 31  GPIO6     ← C1 pos 2    GPIO6          GPIO6              Dial pos 2
Pin 32  GPIO12    (C2 pos 2)    GPIO12         GPIO12             unwired
Pin 33  GPIO13    ← C1 pos 3    GPIO13         GPIO13             Dial pos 3
Pin 34  GND       (C2 pos 3)    GND            GND                unwired
Pin 35  GPIO19    ← C1 pos 4    GPIO19         GPIO19             Dial pos 4
Pin 36  GPIO16    ← C2 pos 4    GPIO16         GPIO16             Dial pos 6
Pin 37  GPIO26    ← C1 pos 5    GPIO26         GPIO26             Dial pos 5
Pin 38  GPIO20    ← C2 pos 5    GPIO20         GPIO20             Dial pos 7
Pin 39  GND       ← C1 pos 6    GND            GND                Dial common
Pin 40  GPIO21    ← C2 pos 6    GPIO21         GPIO21             Dial pos 8
```

\* = printer TX↔RX crossover — Pi pin 8 → printer **RX**, Pi pin 10 → printer **TX**
\* Pi 5: UART0 served by the RP1 southbridge; surfaces as `/dev/ttyAMA0`
† Pi 3B+: PL011 normally lands on the Bluetooth modem; `dtoverlay=disable-bt` redirects it to pins 8/10

**Pins to leave alone on both boards**: 27 / 28 (ID_SD / ID_SC, reserved for HAT EEPROM autodetect).

---

## 7. Cutover

1. **Shut the Pi 5 down**: `sudo shutdown -h now`. Wait for the green LED to stop pulsing.
2. **Disconnect PSU at the wall.** Wait 10 s for caps to discharge.
3. **Unplug** every dupont housing in reverse order: A2 (printer data) → B (button) → C1+C2 (dial) → A1 (power). Note the position-1 marks on each.
4. **Remove the SD card** from the Pi 5. Set the original aside as your rollback artifact — don't reuse it for anything yet.
5. **Insert the cloned card** (with config.txt already edited) into the Pi 3B+.
6. **Confirm the PSU** is a 5V/2.5A micro-USB supply (not the Pi 5's USB-C brick). Wire it to the WAGO joint that feeds A1 on the Pi side — same as before.
7. **Plug A1 only** onto Pi pins 2/4/6 (position-1 / red mark toward the pin-1 corner of the header). Leave A2, B, C1, C2 disconnected for first boot.
8. **Power up.** Red LED solid, green LED flickering for SD activity. The 3B+ takes ~30 s longer than the Pi 5 to reach a usable shell.
9. Once up: `ssh pc-1@pc-1.local` (or via Tailscale at the unchanged IP) — see §8 to verify before plugging the printer.
10. With Pi 5 verified-good in the Pi 3B+, **shut down again** (`sudo shutdown -h now`), reconnect A2 / B / C1 / C2 in the same orientation, and re-power.

---

## 8. Post-boot verification

Run these before reconnecting the printer (A2). The critical check is that `/dev/serial0` points to PL011, not to the BT modem — otherwise prints disappear silently into Bluetooth.

```bash
# Right board
cat /proc/cpuinfo | grep Model
# expect: Raspberry Pi 3 Model B Plus Rev 1.3

# Right UART
ls -l /dev/serial0
# expect: -> ../ttyAMA0     (NOT ttyS0, NOT ttyAMA1, NOT a BT modem)

dmesg | grep -iE 'pl011|uart'
# expect: uart-pl011 ... PL011 rev2 ... ttyAMA0 at MMIO 0x...

# Right GPIO controller for the dial/button driver
ls -l /dev/gpiochip0

# Right power
vcgencmd get_throttled
# expect: throttled=0x0    (any other value = PSU/wiring issue, fix before printing)

# App came back up clean
systemctl status pc-1.service nginx
journalctl -u pc-1 -n 100 --no-pager | grep -iE 'error|fail|trace' | head -20

# Identity preserved
hostname                      # pc-1
tailscale status | head -3    # same IP, same node
curl -sI http://localhost/    # 200 from nginx -> uvicorn
```

Then plug A2 in (with PSU off), power back up, and end-to-end test:

- Dial rotation: each position logs a selection event.
- Short button press on a populated channel: prints.
- Long press (~5 s): Quick Actions card.
- Run a dense raster print (QR code or Sudoku). Watch `vcgencmd get_throttled` from a second SSH session — non-zero means the printer's 4A draw is sagging the rail.

---

## 9. Risks & rollback

| Symptom | Likely cause | Fix |
|---|---|---|
| Prints garbage characters | Wrong baud or wrong UART | Confirm `ls -l /dev/serial0 -> ttyAMA0`; reapply `dtoverlay=disable-bt`; reboot |
| Prints nothing, button works | TX wire not reaching printer header; classic silent-serial trap | Apply the live-pin diagnostic from `feedback_uart_live_pin_diagnostic` — measure TX during a continuous `0x55` stream. 3.3 V swing = wiring problem upstream; ~1.6 V flat = wrong device node |
| `get_throttled` ≠ 0 | PSU under-spec or bad joint | Swap to a known-good 2.5A micro-USB supply; verify WAGO joint with multimeter under load |
| Boot loop after `dtoverlay=disable-bt` | Overlay missing on this firmware version | `raspi-firmware` is 1:1.20260408-1 on this card — overlay exists, but check `/boot/firmware/overlays/disable-bt.dtbo` is present |
| Dial / button silent | `/dev/gpiochip0` not opening | Confirm user is in `gpio` group: `groups pc-1` should include `gpio dialout lp` |
| Doesn't boot at all | Cloned card corrupt, or PSU under-spec | Pop the **original** SD into the Pi 5 and you're back where you started in 5 minutes |

**Hard rollback**: the original SD card from the Pi 5 is your golden master. Keep it sealed in an antistatic bag for at least one release cycle before wiping.

---

## 10. After the migration sticks

Once the 3B+ has run cleanly for ~24 h with a real print job:

- Wipe the original SD card and re-flash for whatever the Pi 5 becomes next.
- Update memory notes: hardware target shifts, but `[[project_paper_console]]` Trixie + Python 3.13 constraint is unchanged on the 3B+.
- Consider whether the PSU-split recommendation from `[[project_pc1_provisioning_state]]` is still relevant — the 3B+ pulls less than the Pi 5, so a single shared 2.5A supply may be marginal for dense raster prints. Watch `get_throttled` for a few weeks.

---

## Appendix: what's deliberately not changing

| Concern | Decision | Reason |
|---|---|---|
| Hostname | Stays `pc-1` | Disk move = identity move |
| Tailscale node | Stays `100.89.148.77` | `tailscaled.state` is on disk |
| Device password | Stays | `/etc/pc1/device_password` on disk |
| SSH host keys | Stay | On disk |
| `config.json` | Stays | App's persisted store |
| Udev override for `serial0` | Stays | Harmless on 3B+, load-bearing if you ever swap card back to Pi 5 |
| nginx, systemd units | Stay | Hardware-agnostic |
| `MemoryMax=256M` on pc-1.service | Stays | 1 GB on 3B+ is the same as 1 GB on Pi 5 1GB |
| `arm_boost=1` in config.txt | Stays | No-op on 3B+, useful on Pi 5 (round-trippable) |
