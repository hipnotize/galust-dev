#!/usr/bin/env python3
"""Checks that every internal link and asset in a built site points to an existing file."""
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.found = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ("href", "src") and value:
                self.found.append(value)


def target(root: Path, page: Path, link: str):
    parts = urlsplit(link)
    if parts.scheme or parts.netloc or not parts.path:
        return None  # external, mailto:, or a pure #fragment
    path = unquote(parts.path)
    base = root if path.startswith("/") else page.parent
    file = (base / path.lstrip("/")).resolve()
    if path.endswith("/") or file.is_dir():
        file = file / "index.html"
    return file


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "public").resolve()
    broken = []
    pages = sorted(root.rglob("*.html"))
    for page in pages:
        parser = Links()
        parser.feed(page.read_text(encoding="utf-8"))
        for link in parser.found:
            file = target(root, page, link)
            if file is not None and not file.exists():
                broken.append(f"{page.relative_to(root)}: {link}")
    for line in broken:
        print("broken:", line)
    print(f"checked {len(pages)} pages, {len(broken)} broken links")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
