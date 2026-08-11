"""Paper Console entry point for the Ticker module.

A low-noise work-notification ticker. A Power Automate flow posts message
*metadata* (source + author, never content) to a VPS buffer; this module
drains that buffer and prints a compact slip.

Cadence comes from the **host's own channel schedule**, not from this
module — bind Ticker to a channel and give that channel a schedule of
"HH:MM" times ten minutes apart. There is no resident task here: the host
fires ``format_ticker_receipt`` on each scheduled minute, already holding
the print reservation, already on a thread-pool worker.

Three trigger paths, all landing in the same function:

  * scheduled fire, armed    -> drain + print (silent if nothing to say)
  * scheduled fire, disarmed -> return immediately, print nothing
  * manual (dial + button)   -> arm, or print status if already armed

``Ticker: Off`` is a second registered module; bind it to any other
channel to disarm.

House rules observed:
  * never acquire the print reservation here — the host already holds it
  * never call reset_buffer/flush_buffer — the host brackets us with them
  * never raise — an escaping exception makes the host print an error slip,
    which on a 10-minute schedule is ~70 slips a day
  * secrets come from the environment, not config.json
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import requests

try:
    from app.module_registry import register_module  # type: ignore
except ImportError:  # running outside a host (CI, direct invocation)
    def register_module(**_kwargs):  # type: ignore[no-redef]
        def decorator(fn):
            return fn
        return decorator

logger = logging.getLogger(__name__)

# 34 chars is the real pixel-wrapped width for body/caption, but selection
# mode widens the left margin — 32 is safe everywhere and never wraps.
LINE_WIDTH = 32
# print_header uppercases and boxes its text; keep it short.
HEADER = "TICKER"
HEADER_ICON = "broadcast"

# Cloudflare Access service-token headers. Environment, not config.json.
ENV_CF_CLIENT_ID = "TICKER_CF_ACCESS_CLIENT_ID"
ENV_CF_CLIENT_SECRET = "TICKER_CF_ACCESS_CLIENT_SECRET"

DRAIN_TIMEOUT_SECONDS = 10.0
# Cap printed author rows so a cumulative drain after an outage can't run
# into the host's max_print_lines truncation.
MAX_AUTHOR_ROWS = 14
# Consecutive failed drains before we spend a slip telling you it's broken.
FAILURE_SLIP_THRESHOLD = 3

CONFIG_SCHEMA = {
    "type": "object",
    "properties": {
        "drain_url": {
            "type": "string",
            "title": "Drain endpoint",
            "description": "e.g. https://ticker.wharry.co.uk/ticker/drain",
            "default": "",
        },
        "print_empty": {
            "type": "boolean",
            "title": "Print empty windows",
            "description": "Off by default. A slip per quiet window trains you to stop reading the roll.",
            "default": False,
        },
    },
}


# --- session state ----------------------------------------------------------
#
# Keyed by a fixed filename rather than module_id: Ticker and Ticker: Off are
# separate module instances with separate ids, and they must share one flag.

def _state_path() -> Path:
    raw = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(raw) / "ticker" / "session.json"


@dataclass
class Session:
    armed: bool = False
    armed_at: str | None = None
    windows: int = 0
    messages: int = 0
    authors: list[str] = field(default_factory=list)
    consecutive_failures: int = 0

    def note(self, count: int, authors: list[str]) -> None:
        self.windows += 1
        self.messages += count
        for a in authors:
            if a not in self.authors:
                self.authors.append(a)

    @property
    def armed_at_dt(self) -> datetime | None:
        if not self.armed_at:
            return None
        try:
            return datetime.fromisoformat(self.armed_at)
        except ValueError:
            return None


def load_session() -> Session:
    path = _state_path()
    if not path.exists():
        return Session()
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return Session(
            armed=bool(data.get("armed", False)),
            armed_at=data.get("armed_at"),
            windows=int(data.get("windows") or 0),
            messages=int(data.get("messages") or 0),
            authors=list(data.get("authors") or []),
            consecutive_failures=int(data.get("consecutive_failures") or 0),
        )
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        logger.warning("Ticker: unreadable session %s (%s); starting fresh", path, exc)
        return Session()


def save_session(session: Session) -> None:
    """Atomic write — temp file, fsync, rename."""
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "armed": session.armed,
        "armed_at": session.armed_at,
        "windows": session.windows,
        "messages": session.messages,
        "authors": session.authors,
        "consecutive_failures": session.consecutive_failures,
    }
    fd, tmp_name = tempfile.mkstemp(prefix=".session.", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


# --- the drain call ---------------------------------------------------------

class DrainError(RuntimeError):
    """Any failure talking to the VPS buffer. Never escapes the trigger."""


def drain_buffer(url: str) -> dict[str, Any]:
    """POST to the drain endpoint; return everything buffered since last drain.

    Cumulative by design. The host drops a scheduled fire outright if the
    printer is busy at that minute (no retry, no catch-up), so a missed tick
    must delay items rather than lose them — the server clears its buffer
    only when we successfully drain it.

    Expected response (we own both ends of this contract):

        {
          "since":  "2026-08-11T14:20:00+01:00",
          "outlook": [{"author": "Nick Sharpe", "count": 2}],
          "teams":   [{"author": "Rob Olney", "kind": "dm", "count": 1}]
        }
    """
    if not url:
        raise DrainError("no drain_url configured")

    headers = {"Accept": "application/json"}
    client_id = os.environ.get(ENV_CF_CLIENT_ID)
    client_secret = os.environ.get(ENV_CF_CLIENT_SECRET)
    if client_id and client_secret:
        headers["CF-Access-Client-Id"] = client_id
        headers["CF-Access-Client-Secret"] = client_secret

    try:
        response = requests.post(url, json={}, headers=headers, timeout=DRAIN_TIMEOUT_SECONDS)
        response.raise_for_status()
        parsed = response.json()
    except requests.RequestException as exc:
        raise DrainError(f"drain failed: {exc}") from exc
    except ValueError as exc:
        raise DrainError("drain returned non-JSON") from exc

    if not isinstance(parsed, dict):
        raise DrainError("drain response was not an object")
    return parsed


# --- rendering --------------------------------------------------------------

def _clock(when: datetime) -> str:
    return when.astimezone().strftime("%H:%M")


def _entries(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    raw = payload.get(key)
    return [e for e in raw if isinstance(e, dict)] if isinstance(raw, list) else []


def _count_of(entry: dict[str, Any]) -> int:
    try:
        return max(1, int(entry.get("count") or 1))
    except (TypeError, ValueError):
        return 1


def _total(entries: list[dict[str, Any]]) -> int:
    return sum(_count_of(e) for e in entries)


def _authors(entries: list[dict[str, Any]]) -> list[str]:
    return [str(e.get("author") or "unknown") for e in entries]


def _render_group(printer, label: str, entries: list[dict[str, Any]], budget: int) -> int:
    """Print one source group. Returns rows consumed from ``budget``."""
    if not entries or budget <= 0:
        return 0
    printer.print_body(f"{label:<10}{_total(entries):>4}")
    shown = 0
    room = LINE_WIDTH - 2 - 4
    for entry in entries:
        if shown >= budget:
            printer.print_body(f"  +{len(entries) - shown} more")
            shown += 1
            break
        author = str(entry.get("author") or "unknown")
        if entry.get("kind") == "dm":
            author = f"{author} (DM)"
        if len(author) > room:
            author = author[: room - 1] + "\u2026"
        printer.print_body(f"  {author:<{room}}{_count_of(entry):>3}")
        shown += 1
    return shown


def print_window(printer, payload: dict[str, Any], *, now: datetime) -> tuple[int, list[str]]:
    """Render one drained window. Returns (message count, author names)."""
    outlook = _entries(payload, "outlook")
    teams = _entries(payload, "teams")

    since = payload.get("since")
    if isinstance(since, str) and len(since) >= 16:
        label = f"{since[11:16]}-{_clock(now)}"
    else:
        label = _clock(now)

    printer.print_header(HEADER, icon=HEADER_ICON)
    printer.print_caption(f">> {label}")
    printer.print_line()
    if not outlook and not teams:
        printer.print_body("quiet.")
    else:
        used = _render_group(printer, "OUTLOOK", outlook, MAX_AUTHOR_ROWS)
        _render_group(printer, "TEAMS", teams, MAX_AUTHOR_ROWS - used)
    printer.feed(1)

    return _total(outlook) + _total(teams), _authors(outlook) + _authors(teams)


def print_armed(printer, *, now: datetime) -> None:
    printer.print_header(HEADER, icon=HEADER_ICON)
    printer.print_caption(f">> ARMED  {_clock(now)}")
    printer.print_line()
    printer.print_body("watching outlook + teams.")
    printer.print_caption("dial ticker: off to stop.")
    printer.feed(1)


def print_disarmed(printer, *, session: Session, now: datetime) -> None:
    printer.print_header("TICKER OFF", icon="pause")
    printer.print_caption(f">> {_clock(now)}")
    printer.print_line()
    started = session.armed_at_dt
    if started is not None:
        elapsed = int((now - started).total_seconds())
        printer.print_body(f"{elapsed // 3600}h {(elapsed % 3600) // 60:02d}m")
    printer.print_body(f"{session.messages} msgs / {len(session.authors)} authors")
    printer.feed(1)


def print_status(printer, *, session: Session, now: datetime) -> None:
    printer.print_header(HEADER, icon=HEADER_ICON)
    printer.print_caption(f">> ALREADY ARMED  {_clock(now)}")
    printer.print_line()
    printer.print_body(f"{session.messages} msgs this session")
    printer.print_caption("dial ticker: off to stop.")
    printer.feed(1)


def print_fault(printer, *, session: Session, now: datetime) -> None:
    printer.print_header(HEADER, icon=HEADER_ICON)
    printer.print_caption(f">> DRAIN FAILING  {_clock(now)}")
    printer.print_line()
    printer.print_body(f"{session.consecutive_failures} polls failed.")
    printer.print_caption("check the vps endpoint.")
    printer.feed(1)


# --- module registration ----------------------------------------------------

@register_module(
    type_id="ticker",
    label="Ticker",
    description="Work-notification ticker. Prints message counts by author on the channel schedule.",
    icon="broadcast",
    offline=False,
    interactive=False,
    category="tools",
    config_schema=CONFIG_SCHEMA,
)
def format_ticker_receipt(
    printer,
    config: dict[str, Any] | None = None,
    module_name: str | None = None,
    module_id: str | None = None,
    scheduled: bool = False,
) -> None:
    """Scheduled fire drains and prints; manual trigger arms."""
    try:
        _ticker_body(printer, config or {}, scheduled=scheduled)
    except Exception:
        # An escaping exception makes the host print an error slip. On a
        # 10-minute schedule that is ~70 slips a day, so swallow it.
        logger.warning("Ticker: trigger failed", exc_info=True)


def _ticker_body(printer, config: dict[str, Any], *, scheduled: bool) -> None:
    now = datetime.now().astimezone()
    session = load_session()
    # Treat config as untrusted — the host does not validate it server-side.
    drain_url = str(config.get("drain_url") or "").strip()
    print_empty = bool(config.get("print_empty", False))

    if not scheduled:
        if session.armed:
            print_status(printer, session=session, now=now)
            return
        if not drain_url:
            printer.print_header(HEADER, icon=HEADER_ICON)
            printer.print_caption(">> NOT CONFIGURED")
            printer.print_line()
            printer.print_body("set drain_url in module config.")
            printer.feed(1)
            return
        save_session(Session(armed=True, armed_at=now.isoformat(timespec="seconds")))
        print_armed(printer, now=now)
        return

    # --- scheduled fire ---
    if not session.armed or not drain_url:
        return  # silent; empty buffer flush is a no-op

    try:
        payload = drain_buffer(drain_url)
    except DrainError as exc:
        session.consecutive_failures += 1
        logger.warning("Ticker: %s (failure %d)", exc, session.consecutive_failures)
        should_warn = session.consecutive_failures == FAILURE_SLIP_THRESHOLD
        save_session(session)
        if should_warn:
            print_fault(printer, session=session, now=now)
        return

    session.consecutive_failures = 0
    has_content = bool(_entries(payload, "outlook") or _entries(payload, "teams"))
    if not has_content and not print_empty:
        save_session(session)
        return

    count, authors = print_window(printer, payload, now=now)
    session.note(count, authors)
    save_session(session)


@register_module(
    type_id="ticker_stop",
    label="Ticker: Off",
    description="Disarm the work-notification ticker.",
    icon="pause",
    offline=True,
    interactive=False,
    category="tools",
    config_schema={"type": "object", "properties": {}},
)
def format_ticker_stop_receipt(
    printer,
    config: dict[str, Any] | None = None,
    module_name: str | None = None,
    module_id: str | None = None,
    scheduled: bool = False,
) -> None:
    try:
        now = datetime.now().astimezone()
        session = load_session()
        if not session.armed:
            printer.print_header("TICKER OFF", icon="pause")
            printer.print_line()
            printer.print_body("ticker is not running.")
            printer.print_caption("dial ticker to arm.")
            printer.feed(1)
            return
        print_disarmed(printer, session=session, now=now)
        save_session(Session())
    except Exception:
        logger.warning("Ticker: stop trigger failed", exc_info=True)
