"""Headlines module — compact front-page list of titles from RSS feeds.

Differs from `news.py` (NewsAPI, per-article QR) and `rss.py` (full article
blocks with QR + summary): this is a paper-conserving headline digest. Titles
only, optional source attribution, no per-article QR.
"""

from typing import Any, Dict, List

from app.config import format_print_datetime
from app.module_registry import register_module
from app.modules.rss import clean_text, get_rss_articles


def _dedupe_by_title(articles: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Drop near-duplicate titles (case-insensitive, whitespace-normalised)."""
    seen = set()
    out: List[Dict[str, Any]] = []
    for article in articles:
        key = " ".join((article.get("title") or "").lower().split())
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(article)
    return out


def _round_robin(articles: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Interleave articles by source so one feed can't dominate the list."""
    buckets: Dict[str, List[Dict[str, Any]]] = {}
    order: List[str] = []
    for article in articles:
        source = article.get("source") or ""
        if source not in buckets:
            buckets[source] = []
            order.append(source)
        buckets[source].append(article)

    merged: List[Dict[str, Any]] = []
    index = 0
    while any(buckets[source] for source in order):
        source = order[index % len(order)]
        if buckets[source]:
            merged.append(buckets[source].pop(0))
        index += 1
    return merged


def get_headlines(config: Dict[str, Any] = None) -> List[Dict[str, Any]]:
    """Fetch and assemble the headline list from configured feeds."""
    if config is None:
        config = {}

    try:
        count = int(config.get("headline_count", 8))
    except (TypeError, ValueError):
        count = 8
    count = max(3, min(count, 15))

    # Pull a generous slice from each feed so round-robin/dedup has stock to work with.
    feed_pool_config = {
        "rss_feeds": config.get("rss_feeds", []),
        "num_articles": 5,
    }
    articles = get_rss_articles(feed_pool_config)

    if config.get("dedupe", True):
        articles = _dedupe_by_title(articles)

    articles = _round_robin(articles)
    return articles[:count]


@register_module(
    type_id="headlines",
    label="Headlines",
    description="Compact list of top headlines from RSS feeds (no summaries, no per-article QR).",
    icon="newspaper",
    offline=False,
    category="content",
    config_schema={
        "type": "object",
        "properties": {
            "rss_feeds": {
                "type": "array",
                "title": "RSS Feed URLs",
                "description": "One headline source per line. The top entries from each feed are interleaved.",
                "items": {"type": "string"},
            },
            "headline_count": {
                "type": "integer",
                "title": "Headlines per print",
                "default": 8,
                "minimum": 3,
                "maximum": 15,
            },
            "show_sources": {
                "type": "boolean",
                "title": "Show source under each headline",
                "default": True,
            },
            "dedupe": {
                "type": "boolean",
                "title": "Drop duplicate titles",
                "default": True,
            },
        },
    },
    ui_schema={
        "headline_count": {"ui:placeholder": "8"},
        "rss_feeds": {
            "items": {"ui:placeholder": "https://feeds.bbci.co.uk/news/rss.xml"}
        },
    },
)
def format_headlines_receipt(
    printer, config: Dict[str, Any] = None, module_name: str = None
):
    """Compile and print the headline digest."""
    config = config or {}
    show_sources = bool(config.get("show_sources", True))

    headlines = get_headlines(config)

    printer.print_header(module_name or "HEADLINES", icon="newspaper")
    printer.print_caption(format_print_datetime())
    printer.print_line()

    if not headlines:
        if not [f for f in config.get("rss_feeds", []) if f and f.strip()]:
            printer.print_body("No feeds configured.")
            printer.print_caption("Add at least one RSS URL in settings.")
        else:
            printer.print_body("No headlines available.")
            printer.print_caption("Feeds reachable but returned no entries.")
        return

    for index, article in enumerate(headlines, start=1):
        title = clean_text(article.get("title", "")).strip() or "Untitled"
        printer.print_text(f"{index}. {title}", style="bold")
        if show_sources:
            source = clean_text(article.get("source", "")).strip()
            if source:
                printer.print_caption(source)
        if index < len(headlines):
            printer.print_text("", style="regular_sm")

    printer.print_line()
