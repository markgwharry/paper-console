# CLAUDE.md — paper-console

## What this repo is

PC-1 (Paper Console 1): a self-hosted thermal-printer appliance running on a Raspberry Pi Zero 2 W. Backend is FastAPI (Python 3.12); settings UI is React + Vite + Tailwind v4. Output is a 58mm thermal receipt printer over TTL serial; input is an 8-position rotary dial and a momentary push button on GPIO.

This is **markgwharry/paper-console**, a fork of [travmiller/paper-console](https://github.com/travmiller/paper-console) (MIT). Upstream is the canonical project — keep changes here within the licence and assume the fork may want to pull upstream changes later, so avoid gratuitous divergence in shared files. If upstream behaviour and a local change conflict, flag it rather than silently resolving.

## Canonical project context

- `readme.md` — setup, architecture, hardware, troubleshooting. Authoritative for behaviour/UX.
- `AGENTS.md` — agent-facing workflow rules (print snapshots, raster preview, settings-UI gallery). **Read this before doing print-output work.**
- `scripts/RELEASE.md` — tag-driven release/OTA workflow, stable/beta lanes, hotfix path.

If instructions conflict, prefer: explicit chat instructions → `CLAUDE.md` → `AGENTS.md` → `readme.md`.

## Environment & tooling rules

- **Always use `./.venv/bin/python`**, never bare `python` or `python3`. The venv is the only place app dependencies are guaranteed to be installed.
- First-time setup: `python3 -m venv .venv && ./.venv/bin/python -m pip install -r requirements-dev.txt && (cd web && npm install)`.
- `requirements.txt` = runtime; `requirements-dev.txt` = runtime + pytest; `requirements-pi.txt` = Pi-only (GPIO etc.). Don't install `requirements-pi.txt` on macOS — it will fail and isn't needed for local work.
- Backend: `./run.sh` (handles port conflicts + stops the `pc-1` systemd unit if present). API at `http://localhost:8000`, docs at `/docs`.
- Frontend dev server: `cd web && npm run dev` → `http://localhost:5173`.
- Tests: `./testing/run_tests.sh` (wraps `pytest -q -s ./testing`). Pass extra args through, e.g. `./testing/run_tests.sh testing/test_core.py -k weather`.
- Lint: `cd web && npm run lint`. No Python linter is wired up — match surrounding style.

## Print-output workflow (important)

Anything that changes what reaches the printer — layout, glyphs, bitmaps, density, alignment, clipping — must be validated through the real print pipeline, not by reading code. Use the feedback loop documented in `AGENTS.md`:

```bash
./.venv/bin/python testing/render_all_prints.py --module-type <type> --output testing/artifacts/debug/feedback_full_print.png
./.venv/bin/python testing/console_raster_preview.py --image testing/artifacts/debug/feedback_full_print.png --dots-width 384 --cols 96
```

- 58mm printer = `--dots-width 384`. Don't change this unless asked.
- Prefer full-print previews over synthetic patterns when evaluating real changes.
- Paste the dot-map output into responses when asking for print QA feedback.
- For a full gallery refresh: `./.venv/bin/python testing/render_all_prints.py` (it wipes and regenerates `*.png` in the target dir — that's intentional).

For settings UI visual checks: `./.venv/bin/python testing/render_settings_ui.py` (Playwright; uses `--install-browser` on first run, `--reuse-servers` if dev servers are already up).

## Code map (most-edited areas)

```
app/
├── main.py                FastAPI app, dial/button loop, print orchestration
├── config.py              Settings/channels/schedules models
├── module_registry.py     @register_module — module self-registration
├── modules/<type>.py      One file per printable module type
├── drivers/               printer_serial / printer_mock, dial_*, button_*
├── routers/wifi.py        WiFi setup endpoints
├── auth.py                Device-password auth + session cookie
├── selection_mode.py      Dial-driven interactive flows (Quick Actions, Adventure)
└── data/                  Bundled offline content (quotes, prompts, history, …)
web/src/
├── App.jsx                Settings UI shell
├── components/            Channel/module editors, modals, schema form
├── WiFiSetup.jsx          Setup AP captive-portal page
└── constants.js, design-tokens.js
testing/                   pytest + render_all_prints.py + render_settings_ui.py
scripts/                   release_build.py, setup_pi.sh, deploy_automated.py
```

### Adding a new printable module

Modules self-register via `@register_module(...)` in `app/module_registry.py` — there's no central list to edit in `main.py`. New module = new file in `app/modules/`, decorated format function, optional `config_schema`/`ui_schema` for the auto-generated settings form. Add a snapshot fixture path via `render_all_prints.py` so it shows up in the gallery.

## Conventions worth knowing

- **Mock drivers exist for everything hardware-touching** (`printer_mock`, `dial_mock`, `button_mock`). Local dev uses them automatically; you don't need a Pi to exercise the full flow. The "Printer" writes to terminal stdout in mock mode.
- **`config.json`** is the persisted settings store. It's gitignored and auto-saved by the running app. Don't commit it. The `.welcome_printed` marker file is similarly local.
- **Secrets/env vars** live in `.env` (gitignored). `.env.example` documents the test-time keys (`PC1_TEST_*`) used to render online-module snapshots. Runtime/production env vars (`PC1_DEVICE_PASSWORD`, `PC1_CORS_ORIGINS`, `PC1_UPDATE_*`, `PC1_LOG_LEVEL`) are documented in `readme.md` §3.
- **Device password** is unified across setup WiFi, settings login, printed setup card, and SSH. Don't split these without strong reason.
- **Logging**: default `WARNING` on device, `WARNING` on Uvicorn, access logs off. Bump via `PC1_LOG_LEVEL=INFO` / `UVICORN_ACCESS_LOG=1` when debugging — don't leave them on.
- **British English in user-facing strings** (printed output, UI copy) where adding new text. Existing strings use US English in places; match the surrounding file rather than mass-converting.

## Release & OTA

- Tag-driven: pushing `v*` triggers `.github/workflows/release-artifacts.yml`, which builds, tests, and publishes the GitHub release the OTA updater consumes.
- `vX.Y.Z` → stable; `vX.Y.Z-beta.N` / `-rc.N` → prerelease (auto-detected from the hyphen).
- Local `./.venv/bin/python scripts/release_build.py --version vX.Y.Z --build-web` is for sanity-checking only — don't commit `release-artifacts/`.
- Branch lanes: `main` = stable-ready; `beta` = prerelease-only. Hotfixes branch from the latest stable tag.
- This is a **fork**: pushing tags here triggers the workflow against `markgwharry/paper-console`, not upstream. Don't push release tags casually.

## Running on the Pi itself

If you (Claude Code) are running **on the PC-1 device** rather than on the development Mac, the rules shift. This section is for that case.

**Fork deployment target:** upstream PC-1 is designed for a Raspberry Pi Zero 2 W, but this fork deploys to a **Raspberry Pi 5 (1GB)** running Pi OS Lite (64-bit) Bookworm. The codebase is hardware-agnostic where it matters — `app/drivers/gpio_ioctl.py` talks to `/dev/gpiochip0` via kernel ioctl, so the dial and button drivers work on the Pi 5's RP1 chip unchanged. Wiring tables in `readme.md` are 40-pin-header compatible across both targets.

### Detect you're on the device

Check, in order:

1. `/etc/pc1/device_managed` exists → you're on a provisioned PC-1. This is the most reliable signal; the file is created by `scripts/setup_pi.sh` and means the device is owned/managed.
2. `cat /proc/cpuinfo | grep -i 'raspberry\|bcm2'` returns a hit → you're on a Pi.
3. `systemctl is-active pc-1.service` returns `active` → the service is running, treat the host as live.

If any of these are true, default to "live device" behaviour below. If none are true, you're on a development host — use the normal workflow in earlier sections.

### What's already there (don't re-do it)

`scripts/setup_pi.sh` is a one-time provisioning step. After it has run, the device has:

- `~/paper-console` cloned and `.venv` populated from `requirements-pi.txt`.
- `pc-1.service` enabled and running under systemd (`MemoryMax=256M`, `Restart=always`, runs `./run.sh`).
- Nginx reverse-proxying `:80` → `127.0.1.1:8000`. Avahi publishing `pc-1.local`.
- Serial console disabled, serial hardware enabled. Printer at `/dev/serial0`.
- User in `lp` and `dialout` groups (printer + serial access).
- Device password at `/etc/pc1/device_password` (`0660`, root:user). The Linux login password is synced to it — don't change either independently.
- Passwordless sudo configured for `systemctl {start,stop,restart,status} pc-1.service`, `nmcli`, the WiFi AP script, `timedatectl`, `chpasswd`, `ntpdate`, and the SSH enable/disable pair. **No other sudo without prompting first.**
- `journald` in RAM (`Storage=volatile`, 16M cap), coredumps disabled, `pc1-storage-guard.timer` running every 6h.

Do **not** re-run `setup_pi.sh` to fix things unless explicitly asked. It's not fully idempotent against an already-provisioned device (it resets the device password if the file is short, runs `chpasswd`, etc).

### How to develop in-place

The expected loop on the Pi is:

```bash
cd ~/paper-console
git pull
sudo systemctl restart pc-1.service
sudo journalctl -u pc-1.service -f   # watch
```

- The service has `Restart=always` with a 5-restarts-per-300s limit. If you push a change that crash-loops, the service stops trying after 5 attempts — `git revert` and `systemctl reset-failed pc-1.service && restart` rather than fighting it.
- For ad-hoc backend work, stop the service and run `./run.sh` interactively. `run.sh` will stop `pc-1.service` itself if it detects an interactive shell — don't double-stop it.
- Don't run two backends at once. Both will try to claim `/dev/serial0` and the printer will misbehave.

### Things that work differently on-device vs the Mac

| Thing | On Mac (dev) | On Pi (device) |
|---|---|---|
| Printer | Mock driver, writes to stdout | **Real thermal printer.** Snapshots consume paper. |
| Dial / button | Mock drivers | Real GPIO. Pressing the physical button triggers prints. |
| `requirements-*.txt` | Use `requirements-dev.txt` | Provisioned with `requirements-pi.txt` (no pytest by default) |
| `npm run dev` / `vite` | Yes | **No.** Pi 5 can run Vite, but a dev server on an appliance is pointless. Build off-device, copy `web/dist/`. |
| `render_settings_ui.py` (Playwright) | Yes | **Avoid.** Chromium fits on 1GB but burns most of the headroom around the 256M-capped service. Do UI snapshots on the Mac. |
| `render_all_prints.py` full sweep | Yes | Avoid. ~20+ PNGs and consumes paper if accidentally routed to the real printer. Pi 5 handles the PIL work fine, but there's no reason to do it on-device. |
| `console_raster_preview.py` (image input) | Yes | Yes — text-only output, safe. |
| Test suite | `./testing/run_tests.sh` | Only after `pip install pytest` into the venv. Prefer running tests off-device. |
| Service control | n/a | `sudo systemctl …` for `pc-1.service` (passwordless) |

### Print testing on real hardware

- **Default to NOT printing.** Use `render_all_prints.py --output testing/artifacts/debug/foo.png` to generate the bitmap, then `console_raster_preview.py --image …` to preview as dot-map text. Only push to the real printer when you specifically want to validate physical output.
- If you do print: one channel/module at a time, not a full sweep. A 384-dot-wide receipt at full length burns through paper quickly.
- The printer draws up to 4A during dense raster blocks. The Pi 5 has stricter input-voltage tolerance than older Pis; under-voltage warnings (`dmesg | grep -i 'voltage\|throttl'`) point at the PSU or wiring, not the code. If the Pi reboots mid-print, suspect the 5V rail first.
- After a print test, check the printer thermal head isn't hot before handling.

### Resource and SD-card constraints

Pi 5 1GB is a comfortable Pi-class device, but still SD-backed and the service is intentionally capped tight. Treat memory and SD writes as scarce.

- The systemd service is capped at `MemoryMax=256M`. That's the binding constraint, not total system RAM. Anything that loads big datasets into memory at startup will OOM-kill the service. Don't widen the cap to paper over a memory regression — fix the regression.
- Don't write big intermediate files under `~/paper-console/testing/artifacts/` — it's on the SD card. If you must generate a gallery on-device, point `--output-dir` at `/tmp/` (tmpfs).
- Don't bump logging to `DEBUG` and leave it on. `PC1_LOG_LEVEL=INFO` is fine for a debug session; reset to `WARNING` after.
- `pc1-storage-guard.timer` will start vacuuming logs/cache at 85% root usage. If you're debugging disk issues, run `/usr/local/bin/pc1-storage-guard.sh` manually rather than letting it surprise you mid-task.
- Pi 5 idles around 50°C in still air and throttles at 80°C. PC-1's duty cycle is mostly idle, so a passive heatsink is enough; if you ever see throttling in `vcgencmd get_throttled`, that's a cooling issue, not a code issue.

### Network and access

- `pc-1.local` resolves via Avahi/mDNS on the same LAN. From off-LAN, use Tailscale.
- If WiFi setup is in progress, the device runs an AP (`PC-1-Setup-XXXX`) and the captive portal is on `http://10.42.0.1`. Don't `nmcli` your way out of it without going through `scripts/wifi_ap_nmcli.sh` — the sudoers rules are scoped to that script.
- SSH password = device password (the file at `/etc/pc1/device_password`). Key-based auth is the preferred path (`ssh-copy-id` from the Mac).

### What to ask before doing on-device

Before any of these, confirm with Mark even if it looks routine:

- `sudo reboot` or `sudo shutdown` (kills the session you're in)
- `git reset --hard`, `git checkout -- .`, or anything that discards uncommitted state on the device
- Editing `/etc/pc1/device_password`, `/etc/sudoers.d/pc-1-wifi`, or anything under `/etc/systemd/system/pc-1.*`
- Re-running `scripts/setup_pi.sh`
- Pulling a non-`main` branch (would normally be deliberate — confirm)
- Anything that touches `config.json` directly (the UI is the supported edit path)

## Things not to do

- Don't run `pip install` against the system Python — always go through `.venv`.
- Don't add Pi-only dependencies (`RPi.GPIO`, `gpiozero`, anything that won't import on macOS) to `requirements.txt` or `requirements-dev.txt` — they belong in `requirements-pi.txt`.
- Don't bypass the print pipeline by writing bytes directly to `/dev/serial0` from app code. Go through `printer_serial` so the mock driver stays equivalent.
- Don't commit `config.json`, `.env`, `release-artifacts/`, `testing/artifacts/`, `.welcome_printed`, or anything under `development/` — they're gitignored for good reasons.
- Don't widen CORS to `*` in committed code. The default origin list in `main.py` is deliberate.
- Don't restructure `app/modules/` or rename module `type_id` values without a migration story — `config.json` files on existing devices reference them by id.
