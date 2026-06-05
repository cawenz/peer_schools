"""
scrape_forbes_rankings.py
=========================

Build data/forbes_top_colleges_<year>.csv from
  https://www.forbes.com/top-colleges/

Forbes' ranking page is JavaScript-rendered with lazy-loaded rows (the
table only contains a handful of rows on initial paint; scrolling down
appends the rest). Static-HTTP scraping (urllib / requests) returns an
empty table. So we use Playwright (headless Chromium) to load the page,
scroll until the row count plateaus, then read the DOM directly.

Forbes uses Cloudflare-style bot defenses. The default headless config
sometimes hits a challenge page; if that happens, re-run with
HEADLESS=0 to launch a visible browser and solve any human-check
manually. The script also writes a snapshot of the page HTML at
data/forbes_page_<year>.html so you can inspect what the scraper saw.

Output files (written to data/):
  forbes_top_colleges_<year>.csv     one row per ranked school
                                     columns: rank, name, state, type
  forbes_page_<year>.html            captured page HTML (audit / debug)

The CSV does NOT contain IPEDS UnitIDs. R's build_forbes() in
schools_pipeline.R matches names + states to schools.csv via the same
normalize-then-fuzzy approach the EADA scraper uses.

Usage:
    pip install playwright
    playwright install chromium
    python R/scrape_forbes_rankings.py              # headless
    HEADLESS=0 python R/scrape_forbes_rankings.py   # visible browser
    YEAR=2025 python R/scrape_forbes_rankings.py    # override year tag

Re-run annually after Forbes releases the new list (typically late
August). If the HTML structure changes, update SELECTORS below.
"""

from __future__ import annotations

import csv
import os
import re
import sys
from pathlib import Path
from typing import List, Optional

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
except ImportError:
    sys.exit(
        "Playwright not installed.\n"
        "  pip install playwright\n"
        "  playwright install chromium\n"
    )

# ----------------------------------------------------------------------------
# Config — adjust if Forbes' DOM changes
# ----------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"

URL = "https://www.forbes.com/top-colleges/"
YEAR = os.environ.get("YEAR", "2025")
HEADLESS = os.environ.get("HEADLESS", "1") != "0"
OUT_CSV = DATA_DIR / f"forbes_top_colleges_{YEAR}.csv"
OUT_HTML = DATA_DIR / f"forbes_page_{YEAR}.html"

# Multiple CSS selectors are tried; Forbes has rotated naming over the
# years (table.fcs-table, ol.list-promo, div[data-ga-track="ranking"], …).
# Order matters — the first that finds rows wins.
ROW_SELECTORS = [
    "table tbody tr",                   # most common
    "div.fcs-table div[role='row']",    # 2024 list shape
    "ol li",                            # fallback
]

# Inside a row, try these for each cell. We don't care about column
# headers — we infer rank from positional / numeric pattern.
CELL_SELECTOR = "td, div[role='cell'], span.col"

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/127.0.0.0 Safari/537.36"
)

# When scrolling, declare "done" after this many consecutive scrolls
# return zero new rows.
SCROLL_STABLE_PASSES = 4
SCROLL_DELTA_PX = 2500
SCROLL_DELAY_MS = 800
MAX_SCROLLS = 200       # hard backstop so a layout glitch can't loop forever
TARGET_ROWS = 500       # Forbes publishes a top-500 list


def _state_code_from(text: str) -> Optional[str]:
    """Pull a trailing two-letter state code out of a cell, e.g. 'MA'.
    Forbes typically renders state as a short suffix or its own cell.
    """
    m = re.search(r"\b([A-Z]{2})\b\s*$", (text or "").strip())
    return m.group(1) if m else None


def _looks_like_rank(text: str) -> Optional[int]:
    """Return the integer rank if the text is a bare rank cell."""
    t = (text or "").strip().lstrip("#")
    if t.isdigit() and 1 <= int(t) <= 999:
        return int(t)
    return None


def scrape() -> List[dict]:
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        ctx = browser.new_context(user_agent=USER_AGENT,
                                   viewport={"width": 1400, "height": 1000})
        page = ctx.new_page()

        print(f"Loading {URL} (headless={HEADLESS}) ...", flush=True)
        page.goto(URL, wait_until="networkidle", timeout=60_000)

        # Forbes sometimes shows a privacy / cookie banner that covers the
        # list. Try to dismiss it. Non-fatal if absent.
        for label in ("Accept", "Accept All", "I Agree", "OK"):
            try:
                page.get_by_role("button", name=label).first.click(timeout=2000)
                print(f"  dismissed banner: {label}")
                break
            except PWTimeout:
                pass
            except Exception:
                pass

        # Find a working row selector before we start scrolling.
        used_selector = None
        for sel in ROW_SELECTORS:
            try:
                page.wait_for_selector(sel, timeout=8_000)
                if page.locator(sel).count() >= 5:
                    used_selector = sel
                    break
            except PWTimeout:
                continue

        if used_selector is None:
            OUT_HTML.write_text(page.content(), encoding="utf-8")
            sys.exit(
                f"Could not find any ranking rows. Page HTML dumped to:\n"
                f"  {OUT_HTML}\n"
                f"Update ROW_SELECTORS in this script after inspecting it."
            )
        print(f"  using row selector: {used_selector}", flush=True)

        # Scroll until row count stops growing for N consecutive passes.
        stable_passes = 0
        last_count = page.locator(used_selector).count()
        for i in range(MAX_SCROLLS):
            page.mouse.wheel(0, SCROLL_DELTA_PX)
            page.wait_for_timeout(SCROLL_DELAY_MS)
            n = page.locator(used_selector).count()
            if n == last_count:
                stable_passes += 1
                if stable_passes >= SCROLL_STABLE_PASSES:
                    break
            else:
                stable_passes = 0
                last_count = n
            if n >= TARGET_ROWS + 5:
                # Some extra padding past 500 to catch ties; stop here.
                break
            if i % 10 == 0:
                print(f"  scroll {i}: {n} rows", flush=True)

        print(f"  final row count: {last_count}", flush=True)
        OUT_HTML.write_text(page.content(), encoding="utf-8")

        # Extract each row's text content, then parse heuristically.
        # Different layouts put rank/name/state in different cells, so
        # we go by content rather than position.
        rows = page.locator(used_selector).all()
        out: List[dict] = []
        for row in rows:
            try:
                cells = [c.strip() for c in row.locator(CELL_SELECTOR)
                                              .all_inner_texts()]
            except Exception:
                continue
            if not cells:
                # Whole row inner_text fallback (semicolon-separated guess)
                txt = (row.inner_text() or "").strip()
                if not txt:
                    continue
                cells = [t.strip() for t in re.split(r"\n+", txt) if t.strip()]

            rank = None
            name = None
            state = None
            forbes_type = None
            for c in cells:
                if rank is None:
                    r = _looks_like_rank(c)
                    if r is not None:
                        rank = r
                        continue
                if state is None:
                    s = _state_code_from(c)
                    if s and len(c) <= 4:    # bare state cell
                        state = s
                        continue
                # The longest non-numeric cell is usually the name; cells
                # like "Private not-for-profit", "Public" are short and
                # often tagged separately. Track best-name candidate.
                if not c.isdigit() and len(c) > 4 and (
                        name is None or len(c) > len(name)):
                    name = c
                    # If the name has a trailing ", MA" style state, capture
                    # that too and clean the name.
                    s2 = _state_code_from(c)
                    if s2 and state is None:
                        state = s2
                        name = re.sub(r",\s*[A-Z]{2}\s*$", "", c).strip()
            # Identify "type" cell loosely
            for c in cells:
                if re.fullmatch(r"(Public|Private(?:\s+not-for-profit)?)",
                                c, re.IGNORECASE):
                    forbes_type = c
                    break

            if rank is None or name is None:
                continue
            out.append({"rank": rank,
                        "name": name,
                        "state": state or "",
                        "type": forbes_type or ""})

        browser.close()

    # Dedupe by (rank, name) — Forbes occasionally renders duplicate rows
    # mid-stream during scroll-load.
    seen = set()
    deduped: List[dict] = []
    for r in sorted(out, key=lambda r: r["rank"]):
        key = (r["rank"], r["name"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(r)
    return deduped


def main() -> int:
    rows = scrape()
    if not rows:
        print("ERROR: no rows extracted. See", OUT_HTML)
        return 2

    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["rank", "name", "state", "type"])
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {OUT_CSV}: {len(rows)} schools")

    # Stat the rank range and a couple sanity hits
    ranks = [r["rank"] for r in rows]
    print(f"  rank range: {min(ranks)} ... {max(ranks)}")
    by_state = {}
    for r in rows:
        by_state[r["state"]] = by_state.get(r["state"], 0) + 1
    top_states = sorted(by_state.items(), key=lambda kv: -kv[1])[:5]
    print(f"  top states: {top_states}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
