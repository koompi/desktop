#!/usr/bin/env python3
"""Web lookup for the sidebar AI. Local SearXNG for search, direct GET for pages.

Stdlib only, so it runs wherever the shell runs. Output is plain text meant to be
read by a small local model, not by a person.
"""
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

SEARX = os.environ.get("KOOMPI_SEARX_URL", "http://127.0.0.1:8888")
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
TIMEOUT = int(os.environ.get("KOOMPI_WEB_TIMEOUT", "20"))
PAGE_CHARS = int(os.environ.get("KOOMPI_WEB_PAGE_CHARS", "6000"))

DROP = {"script", "style", "noscript", "svg", "nav", "footer", "header", "form", "iframe"}


class Extractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.skip = 0
        self.title = ""
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in DROP:
            self.skip += 1
        elif tag == "title":
            self._in_title = True
        elif tag in ("p", "br", "div", "li", "tr", "h1", "h2", "h3", "h4"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in DROP and self.skip:
            self.skip -= 1
        elif tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif not self.skip:
            text = data.strip()
            if text:
                self.parts.append(text)


def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "en,km;q=0.8",
    })
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        ctype = resp.headers.get("Content-Type", "")
        charset = "utf-8"
        if "charset=" in ctype:
            charset = ctype.split("charset=")[-1].split(";")[0].strip() or "utf-8"
        # a 40 MB video would otherwise be read into the shell's address space
        return resp.read(4_000_000).decode(charset, "replace"), ctype


def to_text(raw):
    parser = Extractor()
    try:
        parser.feed(raw)
    except Exception:
        pass
    body = " ".join(parser.parts)
    body = html.unescape(body)
    body = re.sub(r"[ \t]+", " ", body)
    body = re.sub(r"\s*\n\s*", "\n", body)
    body = re.sub(r"\n{3,}", "\n\n", body)
    return parser.title.strip(), body.strip()


def normalise(url):
    if not re.match(r"^https?://", url, re.I):
        url = "https://" + url
    return url


def fetch(url):
    url = normalise(url)
    try:
        raw, ctype = get(url)
    except urllib.error.HTTPError as e:
        return f"Could not open {url}: HTTP {e.code} {e.reason}"
    except Exception as e:
        return f"Could not open {url}: {e}"

    if "json" in ctype:
        return f"# {url}\n\n{raw[:PAGE_CHARS]}"

    title, body = to_text(raw)
    if not body:
        return f"{url} returned no readable text (it is probably rendered by JavaScript)."
    out = f"# {title or url}\nURL: {url}\n\n{body[:PAGE_CHARS]}"
    if len(body) > PAGE_CHARS:
        out += "\n\n[page truncated]"
    return out


def search(query, count=5):
    qs = urllib.parse.urlencode({"q": query, "format": "json", "language": "all"})
    try:
        raw, _ = get(f"{SEARX}/search?{qs}")
        data = json.loads(raw)
    except Exception as e:
        return (f"Search is unavailable ({e}). The local SearXNG at {SEARX} is not "
                f"answering. Start it with: docker start searxng")

    results = data.get("results", [])[:count]
    if not results:
        answers = data.get("answers") or []
        if answers:
            return "\n".join(str(a) for a in answers)
        return f"No results for {query!r}."

    lines = [f"Search results for {query!r}:\n"]
    for i, r in enumerate(results, 1):
        lines.append(f"{i}. {r.get('title', '').strip()}\n   {r.get('url', '')}\n   {(r.get('content') or '').strip()[:300]}")

    # a small model rarely makes the follow-up call on its own, so pay for the
    # top hit up front - it is what answers "what is <site>" in one turn
    top = results[0].get("url")
    if top:
        lines.append(f"\n--- full text of the top result ---\n{fetch(top)}")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 3:
        print("usage: web.py {search|fetch} <query-or-url>")
        return 1
    mode, arg = sys.argv[1], " ".join(sys.argv[2:]).strip()
    if not arg:
        print("Empty query.")
        return 1
    print(search(arg) if mode == "search" else fetch(arg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
