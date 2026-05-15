# Module Ideas — paper-console (Mark's fork)

Brainstorm for new modules and a summary of what's already in the box. Skewed towards your actual workflow: flight test, UAS regulation, Modini ops, MBA-tail productivity, and the home-lab infrastructure on the NAS/VPS.

Implementation surface is small — each module is one file in `app/modules/<type>.py` with a `@register_module(...)` decorator (see `app/module_registry.py`). Many "new module" ideas below can in fact be built with the existing **RSS Feeds** or **Webhook** modules — those are flagged so you don't reinvent.

---

## 1. Existing modules (one-line each)

| Module | Online? | What it prints | Config gist |
|---|---|---|---|
| **News API** | Yes | NewsAPI top headlines | API key, country/category |
| **RSS Feeds** | Yes | Article blocks from arbitrary feeds (+ optional QR) | Feed URL(s), item count |
| **Weather** | Yes | Open-Meteo current + hourly forecast | Uses global lat/long |
| **Email Inbox** | Yes | Unread IMAP messages | Host, user, app password, poll interval |
| **Calendar** | Yes | Month/week/day view from iCal URLs | ICS URL(s), view, range |
| **Webhook** | Yes | GET/POST any HTTP endpoint, with JSON path extraction | URL, method, headers, body, JSON path |
| **Print Webhook** | Yes (incoming) | Whatever an external system POSTs to the device | Token, allowed paths |
| **Astronomy** | Offline | Sunrise/sunset, twilight, moon phase, sun path graphic | Uses global lat/long |
| **System Monitor** | Offline | Host, IP, WiFi, disk/mem bars, uptime, load, CPU temp | None |
| **QR Code** | Offline | URL / WiFi / contact / SMS / email QR | Type + payload |
| **Text / Note** | Offline | Rich text (TipTap JSON): headings, lists, bold/italic, HRs | Document body |
| **Print Image** | Offline | Arbitrary bitmap dithered to 384 dots wide | Image path/upload |
| **Quotes** | Offline | Random quote from bundled DB | Optional category |
| **Journal Prompt** | Offline | Random writing prompt | None |
| **History** | Offline | "On this day" events | Event count |
| **Word of the Day** | Offline (bundled) | Merriam-Webster entry | None |
| **Sudoku** | Offline | Generated puzzle as bitmap grid | Easy / Medium / Hard |
| **Maze** | Offline | Generated maze with start/end markers | Easy / Medium / Hard |
| **Crossword** | Offline | Generated puzzle as bitmap grid | Easy / Medium / Hard |
| **Word Search** | Offline | Generated puzzle as bitmap grid | Easy / Hard |
| **Adventure** | Offline + interactive | Choose-your-own-adventure, dial-driven | Story pack |

Two extension points to remember before proposing anything new:

- **RSS Feeds** will already handle anything that publishes a feed (arXiv categories, Hacker News, gov.uk pages, BBC, Reddit, GitHub release feeds, Companies House profile feeds, most news/blogs). Default to a recommended feed list rather than a new module.
- **Webhook** + **Print Webhook** between them cover most "fetch JSON from a thing" and "let a thing trigger a print" cases. New modules are warranted when the payload needs domain-aware formatting (e.g. a METAR is not just JSON text — it wants a structured layout) or when there's interactive logic.

---

## 2. New module ideas

Ranked roughly by fit to your day. Each entry: **what it is → data source → why it fits → build notes**.

### Aviation & flight ops

**A1. METAR/TAF Briefing** ⭐
- Fetch and pretty-print current METAR + TAF for a configurable list of ICAO codes (default: EGCC, EGAA, EGNT, EGPK + nearest to Spadeadam — EGOS Shawbury or EGOM Spadeadam itself if reported).
- Source: `aviationweather.gov` Data API (free, no key) or the UK Met Office DataPoint aviation feed.
- Why: it's the first thing you look at on a flight test day. A printed copy you can scribble on beats refreshing a tab.
- Build notes: new module. Decode raw METAR into a structured layout (wind, vis, cloud, temp/dew, QNH, remarks) — that's the value add over raw text. ~200 LOC. Offline-when-cached graceful fallback.

**A2. NOTAM Digest** ⭐
- NOTAMs relevant to a chosen area: ICAO codes, point + radius, or a flight test box.
- Source: FAA NOTAM API (works internationally, ICAO-keyed) or UK AIS NOTAM service (account required). FAA is easier to start with.
- Why: same as A1, plus directly de-risks every flight test day. Filterable so it doesn't drown you in irrelevant items.
- Build notes: new module. Filter by FIR / aerodrome / lat-lon-radius; date-range to "today" or "next 24h" by default. Include a configurable severity filter.

**A3. Flight Test Day Card** ⭐⭐
- One-shot printed brief that composes A1 + A2 + global astronomy + danger area status into a single page for a named test site (default Spadeadam, 55.068°N, -2.572°W). Adds a crew/signoff block with empty lines.
- Source: composes A1/A2 outputs + offline astronomy + a static danger-area lookup table.
- Why: this is the killer use case — push the button at 06:30, get the day's brief on paper, walk into the cabin with it. Replaces a Notion page and a Teams DM.
- Build notes: composite module. Best built after A1 and A2 exist. Configurable site (lat/lon, name, ICAO, associated D-area), crew slot count.

**A4. Solar / Space Weather (Kp index, GNSS outlook)**
- Print the 3-day Kp forecast and any active geomagnetic storm alerts.
- Source: NOAA SWPC (free, no key) — `services.swpc.noaa.gov/text/3-day-forecast.txt` and Kp planetary forecast JSON.
- Why: GNSS performance and any HF-style propagation effects matter for UAS testing. A passing reference, not the headline — pairs nicely on the Flight Test Day card.
- Build notes: new module, but small. Could equally be an RSS-extender — SWPC also publishes RSS, so try RSS first.

**A5. ADS-B Overhead**
- Aircraft currently inside a radius of a configurable point. Print callsign, type, altitude, heading, distance.
- Source: `adsb.lol` or `adsb.fi` public API (free, no key); or a local readsb if you set one up.
- Why: nerdy and useful — at Spadeadam it'd show you any local traffic, and at home it's just satisfying.
- Build notes: new module. Trivial fetch, the work is the table layout to fit 384-dot width.

### Work, regulatory, and CAA-side

**B1. CAA / EASA Publication Watch**
- New CAPs, AICs, ORS updates, AMC/GM changes.
- Source: CAA "What's new" RSS (verify it still exists at `caa.co.uk`), EASA news RSS.
- Why: regulatory drift is your blind spot — anything published mid-week tends to be missed until Friday.
- Build notes: **use existing RSS module.** Ship as a curated `aviation_regs.json` feed list rather than a new module. Worth adding a small "recommended feeds" UI affordance later.

**B2. DASA / Defence Funding Opportunities**
- New DASA themed competitions, MOD prior information notices, Defence and Security Accelerator calls.
- Source: DASA RSS (gov.uk) + Contracts Finder API for `Defence` category.
- Why: directly relevant to Modini. Misses on these are expensive.
- Build notes: RSS module covers DASA. Contracts Finder needs the API — could be a Webhook module with JSON path extraction, or a thin new module if filtering gets complex.

**B3. Companies House Watchlist**
- Filings, officer changes, charges, dissolutions for a configured list of company numbers (competitors, suppliers, prime contractors).
- Source: Companies House REST API (free, key required).
- Why: weekly competitor situational awareness without logging into the portal.
- Build notes: new module. Config = list of company numbers + lookback window. Format as one block per company with a "no changes" line when quiet.

**B4. GitHub PR / Action Digest**
- Open PRs and recent failed Actions across a chosen list of repos.
- Source: GitHub REST API (PAT).
- Why: you maintain forks (this one, and likely others). A daily printed digest of "what's blocked on me" is more honest than the inbox.
- Build notes: new module, simple. Group by repo, show author + age + status check summary.

### Productivity (your stack)

**P1. Todoist Today** ⭐
- Print today's tasks (and overdue) as a hand-checkable list. Optionally one project at a time.
- Source: Todoist REST API (you already use it via the MCP server — same token works).
- Why: hand-checking on paper is one of the few rituals that survives a busy day. Reads from the system you already curate.
- Build notes: new module. Config = API token + filter expression (e.g. `(today | overdue) & !#Someday`). Render priority as `!`/`!!`/`!!!` rather than a column. ~150 LOC.

**P2. M365 / Outlook Calendar Today**
- Print today's meetings from Outlook with times, durations, and (optionally) Teams join URLs as QR codes.
- Source: easiest path — publish your calendar as an ICS URL and use the **existing Calendar module**. Harder/cleaner path — Microsoft Graph OAuth.
- Recommendation: **use existing Calendar module with an Outlook ICS URL.** Only build a Graph-based module if you want richer formatting (response status, organiser, Teams QR).

**P3. Focus Sprint Card (Pomodoro)**
- Print a 25-min sprint card: large goal field, three sub-tasks, start/end clock, a "distraction parking" box. Offline, deterministic.
- Why: physical commitment device. Fits the "no screens" ethos of PC-1.
- Build notes: new offline module. ~100 LOC, mostly layout.

**P4. Decision Card (Eisenhower / DACI / WRAP)**
- Print a pre-formatted template for a decision you're about to make. Pick from Eisenhower 2×2, DACI roles, WRAP-style "widen options / reality-test / attain distance / prepare to be wrong" checklist.
- Why: leans on your MBA work; surfaces the structure when you'd otherwise just write notes.
- Build notes: new offline module. Template is config-driven so adding templates later is a JSON edit, not a code change.

### Home, infrastructure, UK-specific

**H1. Octopus Agile Tomorrow** ⭐
- Tomorrow's half-hourly Octopus Agile tariff as a sparkline + cheapest-window summary.
- Source: Octopus public API (free, no auth for the published-rates endpoint).
- Why: actually useful if you're on Agile — plan the EV / dishwasher / heat pump for the cheap hour. Prints around 16:00 once tomorrow's rates publish.
- Build notes: new module. The chart is the value add — a 24-hour bar chart sized to 384 dots. Look at how the weather hourly chart is rendered.

**H2. Met Office UK Weather Warnings**
- Active yellow/amber/red warnings for a configurable list of UK regions.
- Source: Met Office warnings RSS (free).
- Why: useful, but…
- Build notes: **use the existing RSS module** with the regional warnings feed. Worth documenting in a recommended-feeds list, not a new module.

**H3. NAS / Pi-hole / Tailscale Status**
- Daily home-lab dashboard: NAS disk % per pool, Portainer container up/down, Pi-hole queries blocked vs answered, Tailscale online device count.
- Source: each of these has a local API on your Tailnet. Pi-hole API is straightforward; Portainer needs a token; NAS depends on UGreen's API surface.
- Why: catches "something's been red for 3 days" before it bites.
- Build notes: probably one module that aggregates, with each section behind an enable flag. ~250 LOC. Or build each as a Webhook config and aggregate via a channel that contains multiple Webhook modules.

**H4. Bin / Recycling Day**
- Print the night before bin day with which bin to put out.
- Source: most UK councils publish iCal feeds; some have JSON APIs.
- Build notes: **use existing Calendar module** with the council ICS feed. Worth noting in docs.

### Reading & learning

**R1. arXiv Daily Digest**
- New papers in chosen categories (`cs.RO`, `eess.SY`, `cs.AI`, `physics.ao-ph` for your work; pick others for fun).
- Source: arXiv per-category Atom feeds, e.g. `http://export.arxiv.org/rss/cs.RO`.
- Build notes: **use existing RSS module.** Add to recommended feeds.

**R2. Hacker News / Lobsters Digest**
- Top N stories.
- Build notes: **use existing RSS module** with the HN front page RSS or `hnrss.org` filtered feeds.

**R3. Anki Due Count**
- Print today's review backlog from AnkiWeb / AnkiConnect.
- Source: AnkiConnect HTTP API on the desktop, or AnkiWeb scraping (uglier).
- Why: only if you actually use Anki. Skip if not.
- Build notes: new module if you commit; otherwise drop.

### Aviation domain — niche but you'd use them

**X1. SORA OSO Tracker**
- One-shot print of a SAIL-derived OSO list with empty robustness columns to fill in by hand during a review session.
- Source: bundled JSON of OSO definitions per SAIL.
- Why: you're doing this regularly for DART-250. Faster than opening the spreadsheet for a working-group session.
- Build notes: new offline module. Config = SAIL (I–VI). Static content, you'd write the OSO table once.

**X2. Flight Hours Log Card**
- Pre-formatted card: aircraft, date, route, total time, P1/P2, day/night, instrument, remarks. For hand-logging.
- Why: pleasant, fits the ethos. Niche.
- Build notes: trivial offline module.

**X3. UTC / Local Clock Strip**
- Wide bar with UTC + chosen local timezones + key offsets, plus today's sunrise/sunset for a list of sites.
- Why: useful when coordinating with overseas partners or test sites in different zones.
- Build notes: small offline module, uses existing astronomy code.

---

## 3. Suggested build order

If you build any of these, the priority order I'd pick:

1. **A1 METAR/TAF** — biggest daily value, smallest surface, no auth pain.
2. **P1 Todoist Today** — second biggest daily value, you already have the token wired up.
3. **A2 NOTAM Digest** — pairs with A1; the API decision (FAA vs UK AIS) is the real design step.
4. **A3 Flight Test Day Card** — composes A1+A2+astronomy. The "killer app" for you specifically.
5. **H1 Octopus Agile Tomorrow** — different rhythm (prints at ~16:00 on a schedule), proves out the scheduled-print path for tariff data.
6. **B3 Companies House Watchlist** — weekly, low effort, useful.
7. **P3 Focus Sprint Card** — easy win, offline, useful for deep-work blocks.
8. **X1 SORA OSO Tracker** — niche but unique to your fork; nobody upstream will ever build this.

Everything in §2 marked "use existing RSS / Calendar / Webhook" should land first as a recommended-feeds note in `readme.md` rather than code.

---

## 4. Cross-cutting notes

- **Module IDs are device-identifiers.** Existing `config.json` files reference modules by `type_id`. Don't rename a module's `type_id` once you've put a build on a device.
- **Online modules need graceful offline behaviour.** Pattern in `weather.py` is the reference: cache last successful fetch, surface a clear "stale at HH:MM" line, never block the print loop on a hung HTTP call.
- **Auth tokens stored in `config.json`** — that file is gitignored, but it's plaintext on disk. Anything you wouldn't accept as plaintext on the device, route through env vars instead (the existing pattern with `PC1_DEVICE_PASSWORD` is the precedent).
- **Print width is fixed at 384 dots** (58mm). Any chart/graphic that doesn't degrade at that width isn't done.
- **Upstream merge surface:** new modules added in `app/modules/` are low-conflict with upstream (each is its own file). Changes to `module_registry.py`, `main.py`, or `web/src/components/` are higher-risk for merge pain — keep them minimal.
