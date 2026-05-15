# PC-1 Hardware Build Guide (Pi 5, GPIO-powered, dupont-first)

Target: Raspberry Pi 5 (1GB), single shared 5V 5A barrel-jack PSU feeding both Pi (via GPIO) and printer. Connector system: dupont on the Pi side throughout, with the printer's stock JST-XH connectors snipped and re-terminated as dupont. See **§3 Connector strategy** for the reasoning.

For canonical wiring and pin assignments, this guide defers to **readme.md §5 — Hardware Setup**. That table is the source of truth; everything below tells you *how* to build to it.

---

## 1. Bill of materials

| Item | Qty | Notes |
|---|---|---|
| Raspberry Pi 5 (1GB) | 1 | The build target |
| Thermal printer (CSN-A2 / QR204, 58mm TTL) | 1 | With supplied data + power pigtails |
| 1-pole 8-position rotary switch | 1 | Brass dial mechanism per upstream BOM |
| Momentary push button (PCB or panel mount) | 1 | NO contacts |
| 5V 5A barrel-jack PSU + DC jack pigtail | 1 | Regulated. Centre-positive by convention — verify (§4). |
| Inline 5A blade fuse holder + 5A fast-blow fuse | 1 | Goes on the +5V output of the PSU before the splice. Cheap insurance. |
| MicroSD card (16 GB+, Class 10 / A1 or better) | 1 | Pi 5 boots well from SD; SSDs are overkill for this duty cycle |
| Dupont connector housings — 1×3 | 2 | Pi power-in (pins 2/4/6); button (pins 20/21/22) |
| Dupont connector housings — 1×4 | 1 | Printer data (pins 8/10/12/14) |
| Dupont connector housings — 2×6 | 1 | Rotary dial (pins 29–40) |
| Dupont female crimp terminals | ~25 | Allow spares — first crimps are always bin material |
| Stranded hook-up wire — 20 AWG | ~1 m red, ~1 m black | Power pairs (Pi-in and printer-in) |
| Stranded hook-up wire — 24 AWG | ~3 m mixed colours | Data + dial + button |
| WAGO 221-413 lever splice (3-way) **or** 2-position screw terminal block | 1 | PSU fan-out to Pi-in and printer-in. **Do not splice 4A through dupont.** |
| Heatshrink — assorted | a bit | 2.4mm for individual crimps; 6mm for the PSU splice |
| Self-amalgamating or fabric tape | a bit | Strain relief at the dial / button / printer cable exits |

Optional but recommended:

- **Official Raspberry Pi 27W USB-C PSU** — only buy if you hit the conditions in §10. Start without.
- **Passive Pi 5 heatsink** (the official one or any) — fit it. Pi 5 idles at 50°C bare; a heatsink drops that to mid-30s. Not needed for performance, just for headroom.
- **2×20 GPIO header extender / shroud** — if you ever want polarity-keyed connectors, fit a shrouded header. Skip for v1.

---

## 2. Tools

- Dupont / 2.54mm crimping tool (the IWISS SN-28B or equivalent — ~£20). Pliers will work but the joints will be ugly.
- Wire strippers (or a sharp blade if you're confident — 24 AWG is fragile).
- Multimeter with continuity beep and DC voltage mode.
- Soldering iron (only for the PSU pigtail joint if you go that route).
- Heat gun or lighter for heatshrink.
- Small flat-blade screwdriver for the WAGO / terminal block.

---

## 3. Connector strategy (decisions, with reasoning)

### Why dupont on the Pi side, throughout

The Pi GPIO header is a bare 2×20 of 2.54 mm pins. JST-XH housings physically mate with 2.54mm pin headers, but they're 5+ mm wide so you can't fit two side-by-side on adjacent positions. Going dupont-only on the Pi side lets you pack the connections without housing collisions.

### Why snip the printer's stock JSTs

The printer typically arrives with one JST-XH on the data cable and one on the power cable. You could keep them and build pigtails (dupont-on-Pi, JST-on-printer), but that means buying JST-XH male housings + matching crimps + tooling for a one-off build. Snipping and crimping dupont directly onto the printer wires is faster and gives you one connector system across the build.

**The trade-off:** you lose the JST's polarity protection. Mitigated by:
- A 1×3 housing on Pi pins 2/4/6 that can only mate one way once correctly oriented (verified with multimeter at first power-on — §6).
- **Not using dupont for the printer's V+/V- joint.** Use a WAGO or screw terminal. Dupont crimps are rated ~3A and the printer pulls up to 4A under load — see §3 box below.

### Wire gauge by run

| Run | AWG | Why |
|---|---|---|
| PSU → Pi 5V GPIO input (pins 2/4/6) | 20 | Pi 5 pulls up to ~3A peak; doubling pin 2+4 helps. 20 AWG with two parallel crimps is comfortable. |
| PSU → Printer V+/V- | 18 (preferred) or 20 | Printer draws up to 4A during dense raster. Reuse the supplied wires if they're 18 AWG; replace only the tail end. |
| Printer data (TX/RX/DTR/GND) | 24 | Logic-level, mA. The printer's stock 24 AWG is fine — just snip past the JST. |
| Dial positions (8 wires) + common | 24 | Signal only, microamps once pulled up. |
| Button | 24 | Same. |

### Where **not** to use dupont

Anywhere carrying ≥3A continuous. That's a single point: the **printer power** joint. Use a WAGO 221-413 lever splice (cheap, reusable, holds 18–24 AWG mixed) or a small 2-position screw terminal block. This is the one place to spend the extra 2 minutes.

> **Why this matters:** a marginal dupont crimp at 4A heats up under the load of a long QR-code raster, the contact resistance climbs, and you get either intermittent print fails (under-voltage drops the printer mid-line) or, worst case, a melted housing. Easy to avoid.

---

## 4. Wiring summary (defer to readme.md §5)

Don't memorise pin numbers — keep `readme.md` open while you crimp. The three blocks are:

| Block | Pi pins | Wires | Housing |
|---|---|---|---|
| Power + printer data | 2, 6 (power) + 8, 10, 12, 14 (data) | 6 | **1×3** on 2/4/6 (power) and **1×4** on 8/10/12/14 (data) — two assemblies, not one |
| Button | 20, 22 | 2 | **1×3** on 20/21/22 (position 2 unwired) |
| Rotary dial | 29, 31, 33, 35, 37, 39 + 36, 38, 40 | 9 | **2×6** spanning 29–40 (several positions unwired) |

The split power+data into two housings (rather than one 1×7) makes it easier to verify rails at first power-on without the printer's data lines in the way.

---

## 5. Build order

Do these in order. Each stage is independently testable.

### Stage A — PSU bench test (do this before anything else)

1. Cut the barrel jack pigtail to length, strip and tin the ends.
2. Insert the 5A fuse holder inline on the +5V (positive) lead.
3. Plug the PSU into the wall. **Without anything connected on the load side**, measure across the pigtail ends with the multimeter on DC volts:
   - Should read 5.0–5.2 V.
   - **Identify which lead is positive** — most barrel-jack PSUs are centre-positive but verify. Mark the positive lead with red heatshrink or a Sharpie ring. **This step alone prevents the most expensive single mistake in this build.**
4. Unplug the PSU. Leave it unplugged until §6.

### Stage B — Rotary dial cable (2×6 dupont)

Easiest one to do first; longest cable run, so practising crimps here is forgiving.

1. Cut 9 lengths of 24 AWG to your planned dial-to-Pi distance + 50mm slack. Vary colours so positions are visually distinguishable.
2. Strip 4 mm at each end. Crimp a dupont female terminal onto every end (18 crimps total). Tug-test each one — a good crimp doesn't slip.
3. Solder the dial side to the rotary switch lugs, following the pos-1-to-pos-8 + common scheme in `readme.md §5`. Heatshrink each lug. Tie the bundle with a cable wrap or sleeve.
4. Push the Pi-side terminals into a 2×6 dupont housing. **Positions per `readme.md` table:** pin 29 = Pos 1, pin 31 = Pos 2, pin 33 = Pos 3, pin 35 = Pos 4, pin 37 = Pos 5, pin 36 = Pos 6, pin 38 = Pos 7, pin 40 = Pos 8, pin 39 = Common. Leave the four unused positions (corresponding to pins 30, 32, 34) empty.
5. Mark the housing with a Sharpie dot on the side that faces away from the Pi's USB ports — that's your "this end up" guide.

### Stage C — Button cable (1×3 dupont, position 2 blank)

1. Two wires, ~30 cm. Strip and crimp dupont terminals on the Pi end.
2. Solder the far ends to the button's two contacts. NO/NC polarity doesn't matter for a momentary; the firmware reads it as a contact closure.
3. Insert into a 1×3 housing: **position 1 → pin 20 (GND), position 3 → pin 22 (GPIO 25)**. Leave position 2 empty.
4. Mark the housing.

### Stage D — Printer data cable (1×4 dupont)

1. Snip the printer's data JST-XH off, leaving as much wire length as possible.
2. Identify each wire against the printer manual / silk: TX, RX, DTR, GND. **Confirm with continuity beep** to the printer's PCB silkscreen before crimping — the cable colour order varies between manufacturers.
3. Strip 4 mm, crimp dupont terminals.
4. Insert into a 1×4 housing in this order (Pi-pin → printer-line): **8 → Printer RX, 10 → Printer TX, 12 → Printer DTR, 14 → GND**.
5. Note the crossover: Pi TX talks to Printer RX and vice versa. If you wire 8→TX-TX you'll get no print and lots of head-scratching.

### Stage E — Power harness

This is the safety-critical one. Do it after the data work so you're warmed up.

1. Cut two pairs of 20 AWG, red+black:
   - **Pair P (Pi):** ~200 mm. Will terminate in a 1×3 dupont (next step).
   - **Pair T (Printer):** length to match the printer's stock power pigtail.
2. **Pi side — 1×3 dupont on pins 2/4/6:**
   - Solder or crimp the red wire of Pair P into **two** dupont terminals (one for position 1 = pin 2, one for position 2 = pin 4). Both carry +5V; parallelling them doubles the available current at the header.
   - The black wire goes into position 3 = pin 6 (GND).
   - Mark the housing's +5V edge with red heatshrink.
3. **PSU fan-out — WAGO or screw terminal:**
   - Strip ~10 mm of insulation on the PSU pigtail's positive lead. Same for the red wires of Pair P and Pair T.
   - Land all three positive wires (PSU+, Pair P+, Pair T+) into one side of the WAGO / terminal block.
   - Repeat for the negatives.
   - Lever the WAGO closed (or torque the screws), tug-test each wire.
4. **Printer side of Pair T:**
   - Strip the printer's stock power pigtail past the JST, tin both wires.
   - Land Pair T's wires into the printer's pigtail wires via solder + heatshrink, or a second WAGO. **Match red-to-red, black-to-black; verify against the printer's silk one more time** before you heatshrink and commit.

### Stage F — Pi 5 OS image

Before connecting anything, image the SD card per the IMAGER section in the conversation above (Pi OS Lite 64-bit Bookworm, SSH on, locale GB, key auth). Don't connect the Pi to anything yet.

---

## 6. First power-on procedure (this is the careful bit)

Goal: prove the power rail before exposing the printer or Pi to a reversed connection.

1. **Nothing connected to the Pi.** Not the dial, not the button, not the printer (data or power).
2. **Insert the SD card** into the Pi.
3. Plug the 1×3 power harness onto Pi pins 2/4/6. **Visually check** the red edge of the housing is on the side closest to the corner of the Pi PCB (that's the pin-1 corner; pin 2 is the first 5V).
4. Multimeter the WAGO output side: red probe on the +5V wire entering the harness, black probe on GND. Should read 5.0–5.2 V with the PSU still unplugged from the wall (i.e. zero).
5. **Plug the PSU into the wall.** Pi 5 will boot. The red LED lights; the green LED flickers on SD activity.
6. Within 60 s, the Pi should respond to ping at the hostname you set in the Imager. SSH in:
   ```bash
   ssh admin@pc-1.local
   ```
7. **Check for under-voltage immediately:**
   ```bash
   vcgencmd get_throttled
   sudo dmesg | grep -iE 'voltage|throttl|under'
   ```
   `get_throttled=0x0` is what you want. Anything non-zero means the 5V rail is sagging — check the WAGO joints, check the PSU is delivering 5V under load (measure at the WAGO with Pi running).
8. **Unplug the PSU at the wall** (don't tug the harness off a live Pi). Connect the dial 2×6 housing to pins 29–40, double-checking orientation against the Sharpie mark. Connect the button 1×3 housing to pins 20/21/22. **Still don't connect the printer.**
9. Plug the PSU back in. SSH in again. Run the provisioning script:
   ```bash
   cd ~/paper-console     # after git clone
   sudo scripts/setup_pi.sh
   ```
   Answer "pc-1" to the hostname prompt and "Y" to reboot.
10. Once the Pi comes back up, watch the service:
    ```bash
    sudo journalctl -u pc-1.service -f
    ```
    Turn the dial across positions, press the button. You should see selection-mode messages in the log (mock printer is fine; we haven't connected the real one yet). If nothing changes when you turn the dial, that's a wiring fault — debug before going further.

### Stage G — Add the printer

11. **Unplug PSU at the wall.** Wait 10 s.
12. Plug the 1×4 data housing onto Pi pins 8/10/12/14, mark facing the correct way.
13. Connect the printer power leads to the WAGO output (Pair T). Verify red-to-red one final time.
14. Plug PSU in. The printer's status LED should light. Within ~30 s, if this is a fresh image, PC-1 will print the first-boot setup card. If not, push the button briefly.
15. If you smell anything burning, immediately unplug. (You won't — but I'm legally obliged to say it.)

---

## 7. Functional shakedown

In order:

- [ ] Hostname resolves: `ping pc-1.local` from the Mac.
- [ ] Web UI loads: `http://pc-1.local`. Log in with the device password from `/etc/pc1/device_password`.
- [ ] Press the button briefly. Whichever channel the dial is on should print.
- [ ] Print quality: text is sharp, no missing dots, no streaking. If text is faint, the printer's V+ is probably sagging — check the WAGO and the PSU output under load.
- [ ] Long-print test: print a QR code or a Sudoku. Both produce dense raster blocks where the 4A draw is real. Watch `vcgencmd get_throttled` during the print on a separate SSH session.
- [ ] Hold the button ~5 s, release: Quick Actions menu prints. Turn the dial to "2" and press: System Monitor prints (host info, IP, uptime).
- [ ] Power-cycle: pull PSU, wait 10 s, reapply. Pi should reboot cleanly within 60 s and the service should come up green.

---

## 8. Strain relief & enclosure

Once electrically right, do these before the build moves around at all:

- Cable-tie or sleeve each of the three Pi-side bundles individually. Their connectors stress the Pi header in different directions when the case shifts.
- Self-amalgamating tape around the printer's V+/V- WAGO joint (or shrinkwrap if you used solder). 4A through a wiggling joint is what kills these joints over time.
- Anchor the printer's PCB inside the enclosure — don't let it dangle on its cables.
- If the dial cable is long enough to dangle inside the case, dress it to one side; it's the densest bundle and the easiest to abrade.

---

## 9. When to upgrade to the official 27W Pi 5 USB-C PSU

Start with GPIO power. Switch to a dedicated USB-C PSU for the Pi (and keep the barrel-jack PSU for the printer only) if **any** of these happen:

| Symptom | Diagnosis | Fix |
|---|---|---|
| `vcgencmd get_throttled` returns non-zero, even briefly | 5V rail dipping below 4.65 V | USB-C PSU on Pi; split printer onto its own supply |
| `dmesg` shows "Under-voltage detected!" or "Voltage normalised" | Same as above | Same |
| Print quality varies between short and long jobs | Printer V+ sags during dense raster, pulling shared rail down | Split supplies |
| Pi reboots mid-print | Brownout | Split supplies (this is the most expensive symptom — every reboot wears the SD card) |
| Printer fine standalone but Pi reboots when you trigger a print | PSU can deliver 5V at idle but droops under combined load | Split supplies |

Once split: the Pi gets the official USB-C PSU (5V/5A, negotiated high-power mode, full USB current available). The printer keeps the barrel-jack PSU with its WAGO joint to V+/V-. Common ground between the two supplies is **not required** — each load is on its own isolated supply — but it doesn't hurt either if your enclosure happens to bring them together at chassis.

---

## 10. Common build mistakes

1. **Reversed power housing on the Pi.** Verified at Stage A but worth double-checking visually before every power-on during the build.
2. **TX-to-TX instead of TX-to-RX on the printer data.** Easy to do; printer just sits silent. Re-read `readme.md §5` if no print after a working build.
3. **Crimps that look fine but slip out.** Tug-test every crimp at 1 kg. If it pulls out, redo it.
4. **Using a phone charger as the PSU.** Most can't sustain 4A on the 5V rail. If you're testing without the recommended PSU, expect under-voltage warnings.
5. **Forgetting to mark housing orientation.** Future-you will plug it in backwards at 11pm on a deadline. Mark it.
6. **Routing the printer power cable next to the data cable in a tight bundle.** 4A switching noise can confuse 24 AWG TTL data over long runs. Keep them physically separated by at least a few mm where possible, especially the last 100 mm before the printer.
7. **Skipping the fuse.** A 5A fast-blow inline on the PSU output costs 50p and saves the day if anything downstream shorts.

---

## 11. Wiring quick reference (copy from this when crimping)

```
PI 5 GPIO (top view, USB ports towards you, GPIO header on the right)

           3V3  [ 1 ][ 2 ]   5V    <-- 5V IN (red, pos 1 of 1x3)
         GPIO2  [ 3 ][ 4 ]   5V    <-- 5V IN (red, pos 2 of 1x3, paralleled)
         GPIO3  [ 5 ][ 6 ]   GND   <-- GND IN (black, pos 3 of 1x3)
         GPIO4  [ 7 ][ 8 ]   GPIO14 <-- TX -> Printer RX
           GND  [ 9 ][10 ]   GPIO15 <-- RX -> Printer TX
        GPIO17  [11 ][12 ]   GPIO18 <-- DTR -> Printer DTR
        GPIO27  [13 ][14 ]   GND    <-- Signal GND -> Printer GND
        GPIO22  [15 ][16 ]   GPIO23
           3V3  [17 ][18 ]   GPIO24
        GPIO10  [19 ][20 ]   GND    <-- Button GND (pos 1 of 1x3)
         GPIO9  [21 ][22 ]   GPIO25 <-- Button signal (pos 3 of 1x3)
        GPIO11  [23 ][24 ]   GPIO8
           GND  [25 ][26 ]   GPIO7
         GPIO0  [27 ][28 ]   GPIO1
         GPIO5  [29 ][30 ]   GND    <-- Dial Pos 1   | (empty)
         GPIO6  [31 ][32 ]   GPIO12 <-- Dial Pos 2   | (empty)
        GPIO13  [33 ][34 ]   GND    <-- Dial Pos 3   | (empty)
        GPIO19  [35 ][36 ]   GPIO16 <-- Dial Pos 4   | Dial Pos 6
        GPIO26  [37 ][38 ]   GPIO20 <-- Dial Pos 5   | Dial Pos 7
           GND  [39 ][40 ]   GPIO21 <-- Dial Common  | Dial Pos 8
```

Print this page and tape it to the bench. Cross off each connection as you make it.
