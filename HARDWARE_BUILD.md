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
| Dupont connector housings — 1×6 | 2 | Rotary dial — one per row of the GPIO header (pins 29–39 odd, pins 30–40 even) |
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

## 4. Housing specification (which terminal lands on which Pi pin)

This is the authoritative table for every housing. The build stages in §5 reference these by name (A1, A2, B, C1, C2).

### Orientation reference

You need a consistent way to know which end of a housing is "position 1". Use this rule throughout:

- On the Pi, **Pin 1** is marked with a small **square pad** on the silkscreen (every other pad is round). It's at one corner of the 40-pin header.
- **Position 1 of every housing always lands on the lowest-numbered Pi pin in that housing.**
- That means: when you slide the housing onto the header, you orient it so position 1 (the end of the housing with terminal #1) is closest to the Pi's square-pad pin-1 corner.

Mark each housing on its position-1 end with a Sharpie dot or coloured heatshrink so you can see orientation at a glance. Several of the housings are wired symmetrically and **will** mate either way round if you don't enforce this.

Pin numbering recap: Pi pins alternate across two rows, **odd row = 1, 3, 5, 7… ; even row = 2, 4, 6, 8…**. A 1×N housing on a 2-row header only touches one row. The dial uses two 1×6 housings, one per row, plugged on simultaneously.

### Housing A1 — Pi power input (1×3, on pins 2 / 4 / 6, even row)

Two parallel +5V wires (one feeds each of the two 5V pins, doubling current capacity) plus one GND wire.

| Position | Pi pin | Wire | Goes to |
|:---:|:---:|---|---|
| 1 | 2 | Red (~200 mm, 20 AWG) | WAGO PSU + rail |
| 2 | 4 | Red (~200 mm, 20 AWG) | WAGO PSU + rail (paralleled) |
| 3 | 6 | Black (~200 mm, 20 AWG) | WAGO PSU − rail |

Mark position 1 (red side) with red heatshrink.

### Housing A2 — Printer data (1×4, on pins 8 / 10 / 12 / 14, even row)

| Position | Pi pin | Pi function | Wire to printer |
|:---:|:---:|---|---|
| 1 | 8 | GPIO 14 = UART TX | Printer **RX** |
| 2 | 10 | GPIO 15 = UART RX | Printer **TX** |
| 3 | 12 | GPIO 18 = DTR | Printer **DTR** |
| 4 | 14 | GND (signal) | Printer **GND** |

Note the crossover: Pi TX (pin 8) talks to Printer RX, Pi RX (pin 10) listens to Printer TX. **Pi TX–Printer TX is the most common wiring mistake on this build.** Always verify against the printer's silkscreen with a continuity test before crimping.

A1 and A2 are physically adjacent on the GPIO even row: pin 6 (A1's last position) and pin 8 (A2's first position) are consecutive pins. The two housings butt against each other on the header.

### Housing B — Button (1×3, on pins 20 / 21 / 22, even row, position 2 blank)

Pin 21 is GPIO 9, which we don't use. Leave the housing's middle slot unwired so the housing keeps its 1×3 shape (a 1×2 won't span pins 20 to 22 — they're not adjacent).

| Position | Pi pin | Wire |
|:---:|:---:|---|
| 1 | 20 | Black (GND) — to button terminal **A** |
| 2 | 21 | (empty — no terminal, no wire) |
| 3 | 22 | Coloured (signal — GPIO 25) — to button terminal **B** |

Button is non-polarised (momentary NO contact). Either button terminal can be "A" or "B".

### Housing C1 — Dial odd row (1×6, on pins 29 / 31 / 33 / 35 / 37 / 39)

All six positions wired. Sits on the **inner row** of the GPIO header (odd pins).

| Position | Pi pin | Pi function | Wire to dial |
|:---:|:---:|---|---|
| 1 | 29 | GPIO 5 | Dial lug "1" (Position 1) |
| 2 | 31 | GPIO 6 | Dial lug "2" (Position 2) |
| 3 | 33 | GPIO 13 | Dial lug "3" (Position 3) |
| 4 | 35 | GPIO 19 | Dial lug "4" (Position 4) |
| 5 | 37 | GPIO 26 | Dial lug "5" (Position 5) |
| 6 | 39 | GND | Dial lug **"C"** (common) |

### Housing C2 — Dial even row (1×6, on pins 30 / 32 / 34 / 36 / 38 / 40, first 3 positions blank)

Sits on the **outer row** of the GPIO header (even pins). Only the last three positions are wired — pins 30, 32, 34 are GND / GPIO 12 / GND, which we don't use.

| Position | Pi pin | Pi function | Wire to dial |
|:---:|:---:|---|---|
| 1 | 30 | (GND, unused) | (empty) |
| 2 | 32 | (GPIO 12, unused) | (empty) |
| 3 | 34 | (GND, unused) | (empty) |
| 4 | 36 | GPIO 16 | Dial lug "6" (Position 6) |
| 5 | 38 | GPIO 20 | Dial lug "7" (Position 7) |
| 6 | 40 | GPIO 21 | Dial lug "8" (Position 8) |

C1 and C2 plug onto the GPIO header **simultaneously, side-by-side** — one on the odd row, one on the even row. Together they occupy the full bottom-of-header block.

### Summary diagram

```
                                Pi 5 GPIO header (top edge of board)
                       odd row (inner)              even row (outer)
                       ─────────────────────        ─────────────────────
   pin-1 corner        Pin  1  3.3V                 Pin  2  5V   ┐
                       Pin  3  GPIO2                Pin  4  5V   │  A1 (1×3)
                       Pin  5  GPIO3                Pin  6  GND  ┘
                       Pin  7  GPIO4                Pin  8  GPIO14 ┐
                       Pin  9  GND                  Pin 10  GPIO15 │  A2 (1×4)
                       Pin 11  GPIO17               Pin 12  GPIO18 │
                       Pin 13  GPIO27               Pin 14  GND    ┘
                       Pin 15  GPIO22               Pin 16  GPIO23
                       Pin 17  3.3V                 Pin 18  GPIO24
                       Pin 19  GPIO10               Pin 20  GND    ┐
                       Pin 21  GPIO9                Pin 22  GPIO25 ┘  B (1×3)
                       Pin 23  GPIO11               Pin 24  GPIO8
                       Pin 25  GND                  Pin 26  GPIO7
                       Pin 27  GPIO0                Pin 28  GPIO1
   ┌  C1 (1×6) ───┐  Pin 29  GPIO5                Pin 30  GND    ┐
   │              │  Pin 31  GPIO6                Pin 32  GPIO12 │
   │              │  Pin 33  GPIO13               Pin 34  GND    │  C2 (1×6)
   │              │  Pin 35  GPIO19               Pin 36  GPIO16 │
   │              │  Pin 37  GPIO26               Pin 38  GPIO20 │
   └──────────────┘  Pin 39  GND                  Pin 40  GPIO21 ┘
   pin-40 corner
```

### Why split power and data into A1 + A2 rather than one 1×7

Lets you bring up the Pi with just A1 plugged in to verify the 5V rail, before any printer signal can introduce a fault. Once A1 is proven safe (§6), A2 plugs in alongside without disturbing it.

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

### Stage B — Rotary dial cables (C1 + C2, two 1×6 dupont)

Easiest one to do first; longest cable run, so practising crimps here is forgiving.

1. Cut 9 lengths of 24 AWG to your planned dial-to-Pi distance + 50 mm slack. Vary colours so each dial position is visually distinguishable from the next — you'll thank yourself when debugging.
2. Strip 4 mm at each end. Crimp a dupont female terminal onto every end (18 crimps total — 9 wires, 2 ends each). Tug-test each one — a good crimp doesn't slip when pulled at ~1 kg.
3. Solder the dial side to the rotary switch lugs per the dial column in tables **C1** and **C2** in §4. Heatshrink each lug. Sleeve or cable-tie the 9-wire bundle.
4. Pi side — load housing **C1** (1×6) per §4 table:
   - Positions 1–5 = dial lugs "1"–"5"
   - Position 6 = dial common
5. Pi side — load housing **C2** (1×6) per §4 table:
   - Positions 1, 2, 3 empty (no terminal, no wire)
   - Position 4 = dial lug "6"
   - Position 5 = dial lug "7"
   - Position 6 = dial lug "8"
6. Mark the **position-1 end** of each housing with a red Sharpie dot or a sliver of red heatshrink. Both housings will mate either way round if you don't enforce orientation; the dot is your safety net.

C1 plugs onto the GPIO header's **inner row** (odd pins 29/31/33/35/37/39); C2 plugs onto the **outer row** (even pins 30/32/34/36/38/40). They sit side-by-side at the pin-40 end of the header.

### Stage C — Button cable (housing B, 1×3 dupont with position 2 blank)

1. Two wires, ~30 cm of 24 AWG. Strip and crimp dupont terminals on the Pi end.
2. Solder the far ends to the button's two contacts (button is non-polarised; either contact is fine).
3. Load housing **B** per §4 table:
   - Position 1 (GND, black) — to button terminal A
   - Position 2 — empty
   - Position 3 (signal, coloured) — to button terminal B
4. Mark the position-1 end.

### Stage D — Printer data cable (housing A2, 1×4 dupont)

1. Snip the printer's data JST-XH off, leaving as much wire length as possible on the printer side.
2. **Identify each wire** against the printer's silkscreen with the multimeter's continuity beep — probe from the cut end of each wire to the corresponding labelled pad on the printer PCB (TX, RX, DTR, GND). Note which colour is which on a bit of masking tape; cable colour conventions vary between manufacturers and you must not assume.
3. Strip 4 mm, crimp dupont terminals on the Pi end.
4. Load housing **A2** per §4 table:
   - Position 1 — Printer **RX** wire (this goes to Pi TX, pin 8)
   - Position 2 — Printer **TX** wire (goes to Pi RX, pin 10)
   - Position 3 — Printer **DTR** wire (pin 12)
   - Position 4 — Printer **GND** wire (pin 14)
5. The TX↔RX crossover is the most common bug on this build. If you wire A2 by Pi-function names alone ("TX in position 1") you'll end up with TX-to-TX and silence. Always wire by **printer label** as above.

### Stage E — Power harness (housing A1 + WAGO fan-out)

This is the safety-critical one. Do it after the data work so you're warmed up on crimping.

1. Cut three power wires for Pair P (Pi side):
   - **2 × red, 20 AWG, ~200 mm** — one wire per +5V pin (positions 1 and 2 of A1, which sit on Pi pins 2 and 4).
   - **1 × black, 20 AWG, ~200 mm** — GND (position 3 of A1, Pi pin 6).
2. Cut Pair T (printer side): red+black 20 AWG (or 18 AWG if available), length to match the printer's stock power pigtail.
3. **Pi-side housing A1:** crimp dupont terminals on one end of all three Pair P wires. Load into the 1×3 housing per §4 table A1:
   - Position 1 (Pi pin 2) — red A
   - Position 2 (Pi pin 4) — red B
   - Position 3 (Pi pin 6) — black
4. Mark the position-1 end of A1 with red heatshrink. This is the housing most catastrophic to plug backwards — putting +5V on pin 6 (GND) won't immediately fry anything, but +5V on pin 8 (GPIO 14) will kill the GPIO and possibly the SoC. Mark it.
5. **PSU fan-out — WAGO or screw terminal:**
   - Strip ~10 mm of insulation on the PSU pigtail's positive lead. Same for **both** red wires of Pair P (the unterminated ends) **and** the red wire of Pair T.
   - Land all four positive wires (PSU+, Pair P red A, Pair P red B, Pair T red) into one side of the WAGO 221-413 (or one screw terminal of the block).
   - Repeat for the negatives — three wires (PSU−, Pair P black, Pair T black) into the negative side.
   - Lever the WAGO closed (or torque the screws), tug-test each wire.
6. **Printer side of Pair T:**
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
8. **Unplug the PSU at the wall** (don't tug the harness off a live Pi). Connect the dial housings: **C1** onto the odd row (pins 29/31/33/35/37/39) and **C2** onto the even row (pins 30/32/34/36/38/40), both with position-1 marks toward the pin-1 corner. Connect housing **B** to pins 20/21/22. **Still don't connect the printer.**
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
12. Plug housing **A2** onto Pi pins 8/10/12/14, position-1 mark towards the pin-1 corner (so A1 and A2 sit cleanly butted-up on the even row).
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
PI 5 GPIO (pin-1 corner at top; odd row left, even row right)

                                                                 ┌─ A1 pos 1
           3V3  [ 1 ][ 2 ]   5V    <-- A1 pos 1   +5V (red A) ───┤  (1×3)
         GPIO2  [ 3 ][ 4 ]   5V    <-- A1 pos 2   +5V (red B) ───┤
         GPIO3  [ 5 ][ 6 ]   GND   <-- A1 pos 3   GND (black) ───┘
         GPIO4  [ 7 ][ 8 ]  GPIO14 <-- A2 pos 1   ── Printer RX ┐
           GND  [ 9 ][10 ]  GPIO15 <-- A2 pos 2   ── Printer TX │  A2
        GPIO17  [11 ][12 ]  GPIO18 <-- A2 pos 3   ── Printer DTR│  (1×4)
        GPIO27  [13 ][14 ]   GND   <-- A2 pos 4   ── Printer GND┘
        GPIO22  [15 ][16 ]  GPIO23
           3V3  [17 ][18 ]  GPIO24
        GPIO10  [19 ][20 ]   GND   <-- B pos 1    Button GND ─────┐ B
         GPIO9  [21 ][22 ]  GPIO25 <-- B pos 3    Button signal ──┘ (1×3, p2 blank)
        GPIO11  [23 ][24 ]  GPIO8
           GND  [25 ][26 ]  GPIO7
         GPIO0  [27 ][28 ]  GPIO1
         GPIO5  [29 ][30 ]   GND   <-- C1 pos 1 Dial Pos 1  | C2 pos 1 (empty)
         GPIO6  [31 ][32 ]  GPIO12 <-- C1 pos 2 Dial Pos 2  | C2 pos 2 (empty)
        GPIO13  [33 ][34 ]   GND   <-- C1 pos 3 Dial Pos 3  | C2 pos 3 (empty)
        GPIO19  [35 ][36 ]  GPIO16 <-- C1 pos 4 Dial Pos 4  | C2 pos 4 Dial Pos 6
        GPIO26  [37 ][38 ]  GPIO20 <-- C1 pos 5 Dial Pos 5  | C2 pos 5 Dial Pos 7
           GND  [39 ][40 ]  GPIO21 <-- C1 pos 6 Dial Common | C2 pos 6 Dial Pos 8

Housing summary:
  A1: 1×3 on pins 2/4/6   (Pi power in)
  A2: 1×4 on pins 8/10/12/14   (printer data)
  B : 1×3 on pins 20/21/22, pos 2 blank   (button)
  C1: 1×6 on pins 29/31/33/35/37/39   (dial odd row, all positions used)
  C2: 1×6 on pins 30/32/34/36/38/40   (dial even row, pos 1-3 blank)
```

Print this page and tape it to the bench. Cross off each connection as you make it.
