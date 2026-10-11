#!/usr/bin/env python3
"""Check the static delivery without installing dependencies or changing Git state."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote
import hashlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 8_388_608


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


class AssetLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in {"src", "href"} and value:
                self.links.append(value)


def main():
    source = {p.relative_to(ROOT / "site") for p in (ROOT / "site").rglob("*") if p.is_file()}
    exported = {p.relative_to(ROOT / "dist") for p in (ROOT / "dist").rglob("*") if p.is_file()}
    assert source == exported, "source/export file mismatch"
    for relative in source:
        src, dst = ROOT / "site" / relative, ROOT / "dist" / relative
        assert not src.is_symlink() and not dst.is_symlink(), "runtime symlink"
        assert src.read_bytes() == dst.read_bytes(), f"stale export: {relative}"
        if src.suffix in {".html", ".js"}:
            assert not re.search(r"\b0x[0-9a-fA-F]{40}\b", src.read_text()), "embedded token address"
        if src.suffix == ".html":
            parser = AssetLinks()
            parser.feed(src.read_text())
            for value in parser.links:
                url = urlparse(value)
                if url.scheme or url.netloc or not url.path:
                    continue
                assert not value.startswith("/"), f"non-relative HTML asset/link: {value}"
                target = (src.parent / unquote(url.path)).resolve()
                assert target.exists(), f"missing asset/link: {src}: {value}"
    protected = ["foundry.toml", "foundry.lock", "remappings.txt", ".gitmodules", "lib", "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", ".github"]
    assert not git("diff", "--name-only", "HEAD", "--", *protected).strip(), "protected files changed"
    assert not any(line.startswith(b"160000 ") for line in git("ls-files", "--stage").splitlines()), "submodule present"
    files = [ROOT / p.decode() for p in git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0") if p]
    assert len(files) == len(set(files)), "duplicate candidate files"
    for file in files:
        relative = file.relative_to(ROOT)
        assert not file.is_symlink(), f"symlink: {relative}"
        assert not any(part in {"node_modules", ".npm", ".cache", "__pycache__", ".playwright-mcp"} for part in relative.parts), f"packaging artifact: {relative}"
        assert file.suffix not in {".tgz", ".tar", ".zip"}, f"dependency/archive artifact: {relative}"
        assert not file.name.startswith(".env"), f"environment file: {relative}"
    total = sum(file.stat().st_size for file in files)
    assert total < LIMIT, f"candidate file payload exceeds 8 MiB: {total}"
    runtime = sum((ROOT / "dist" / relative).stat().st_size for relative in exported)
    print(f"PASS: {len(exported)} exact runtime files, {runtime} bytes; relative assets; no embedded TEST address; protected files unchanged; no submodule, caches or archives")
    print(f"PASS: {len(files)} submission candidate files, {total} bytes ({total / 1024**2:.3f} MiB) uncompressed, below {LIMIT} bytes")
    print("Runtime SHA-256 index:")
    for relative in sorted(exported):
        print(hashlib.sha256((ROOT / "dist" / relative).read_bytes()).hexdigest(), relative)


if __name__ == "__main__":
    main()
