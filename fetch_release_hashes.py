#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx[socks]>=0.27,<1"]
# ///

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import tomllib
from pathlib import Path
from typing import Any

import httpx


GITHUB_API = "https://api.github.com/repos/{repo}/releases/latest"
DOWNLOAD_URL = "https://github.com/{repo}/releases/download/{tag}/{asset}.sha256sum"


def get_latest_tag(client: httpx.Client, repo: str, github_token: str | None) -> str:
    url = GITHUB_API.format(repo=repo)
    headers: dict[str, str] = {"Accept": "application/vnd.github+json"}
    if github_token:
        headers["Authorization"] = f"Bearer {github_token}"
    try:
        resp = client.get(url, headers=headers)
        resp.raise_for_status()
    except httpx.HTTPStatusError as exc:
        raise RuntimeError(f"HTTP {exc.response.status_code} while fetching {url}") from exc
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Network error while fetching {url}: {exc}") from exc
    data = resp.json()
    tag = data.get("tag_name")
    if not isinstance(tag, str) or not tag:
        raise RuntimeError(f"Missing tag_name in latest release for {repo}")
    return tag


def parse_sha256sum(text: str, repo: str, asset: str) -> str:
    line = text.strip().splitlines()
    if not line:
        raise RuntimeError(f"Empty checksum response for {repo} {asset}")
    checksum = line[0].split()[0]
    if len(checksum) != 64 or not all(c in "0123456789abcdefABCDEF" for c in checksum):
        raise RuntimeError(f"Invalid sha256 in checksum response for {repo} {asset}")
    return checksum.lower()


def sha256_hex_to_sri(hex_hash: str) -> str:
    try:
        raw = bytes.fromhex(hex_hash)
    except ValueError as exc:
        raise RuntimeError(f"Invalid hex sha256: {hex_hash}") from exc
    b64 = base64.b64encode(raw).decode("ascii")
    return f"sha256-{b64}"


def load_repos(path: Path) -> list[dict[str, Any]]:
    with path.open("rb") as f:
        raw = tomllib.load(f)
    repos = raw.get("repos")
    if not isinstance(repos, list):
        raise RuntimeError(f"{path} must contain a 'repos' array")
    parsed: list[dict[str, Any]] = []
    for idx, repo_item in enumerate(repos):
        if not isinstance(repo_item, dict):
            raise RuntimeError(f"repos[{idx}] must be a table")
        repo = repo_item.get("repo")
        assets = repo_item.get("assets", ["geoip.dat", "geosite.dat"])
        if not isinstance(repo, str) or "/" not in repo:
            raise RuntimeError(f"repos[{idx}].repo must be like 'owner/name'")
        if not isinstance(assets, list) or not all(isinstance(a, str) for a in assets):
            raise RuntimeError(f"repos[{idx}].assets must be a string array")
        parsed.append({"repo": repo, "assets": assets})
    return parsed


def process_repo(
    client: httpx.Client, repo: str, assets: list[str], github_token: str | None
) -> dict[str, Any]:
    tag = get_latest_tag(client, repo, github_token)
    out: dict[str, Any] = {"repo": repo, "release": tag, "assets": {}}
    for asset in assets:
        sum_url = DOWNLOAD_URL.format(repo=repo, tag=tag, asset=asset)
        try:
            resp = client.get(sum_url)
            resp.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise RuntimeError(f"HTTP {exc.response.status_code} while fetching {sum_url}") from exc
        except httpx.HTTPError as exc:
            raise RuntimeError(f"Network error while fetching {sum_url}: {exc}") from exc
        checksum_text = resp.text
        hex_sum = parse_sha256sum(checksum_text, repo, asset)
        out["assets"][asset] = {
            "sha256_hex": hex_sum,
            "sha256_sri": sha256_hex_to_sri(hex_sum),
        }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch latest GitHub release tags and .sha256sum values and write JSON."
    )
    parser.add_argument(
        "-i", "--input", default="repos.toml", help="Input TOML file (default: repos.toml)"
    )
    parser.add_argument(
        "-o", "--output", default="hashes.json", help="Output JSON file (default: hashes.json)"
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    github_token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")

    repos = load_repos(input_path)
    result: dict[str, Any] = {"repos": {}}
    with httpx.Client(
        headers={"User-Agent": "uv-python-script"}, timeout=30.0, follow_redirects=True
    ) as client:
        for repo_cfg in repos:
            repo_result = process_repo(client, repo_cfg["repo"], repo_cfg["assets"], github_token)
            result["repos"][repo_cfg["repo"]] = {
                "release": repo_result["release"],
                "assets": repo_result["assets"],
            }

    output_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
