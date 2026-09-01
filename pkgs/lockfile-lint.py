#!/usr/bin/env python3
"""Lint a consumer flake.lock against platform policy.

Checks:
  1. The `platform` input is present and resolves to an approved URL.
  2. Every nixpkgs node follows platform's nixpkgs (no second nixpkgs).
  3. No input resolves to an unapproved host.

Usage:
    lockfile-lint path/to/flake.lock
"""
import json
import sys

APPROVED_HOSTS = {"ghe.corp", "artifactory.corp", "flakehub.com"}
APPROVED_PLATFORM_REPOS = {("platform", "flake")}


def node_url(node):
    original = node.get("original", {}) or node.get("locked", {})
    typ = original.get("type")
    if typ == "github":
        host = original.get("host", "github.com")
        return host, f"{original.get('owner')}/{original.get('repo')}"
    if typ in ("git", "tarball", "file"):
        url = original.get("url", "")
        host = url.split("//")[-1].split("/")[0].split("@")[-1]
        return host, url
    return original.get("type", "unknown"), json.dumps(original, sort_keys=True)


def main(path):
    with open(path) as fh:
        lock = json.load(fh)

    nodes = lock.get("nodes", {})
    root = nodes.get("root", {})
    root_inputs = root.get("inputs", {})
    errors = []

    # 1. platform input present
    if "platform" not in root_inputs:
        errors.append(
            "no `platform` input; run `nix flake init -t platform#go-service` "
            "or add it manually"
        )

    # 2. exactly one nixpkgs in the graph, and it comes from platform
    nixpkgs_nodes = [
        name
        for name, node in nodes.items()
        if name != "root" and "nixpkgs" in name.lower()
    ]
    if len(nixpkgs_nodes) > 1:
        errors.append(
            f"{len(nixpkgs_nodes)} nixpkgs nodes in the graph ({', '.join(sorted(nixpkgs_nodes))}); "
            "add `nixpkgs.follows = \"platform/nixpkgs\"` to every input that "
            "declares its own"
        )

    # In flake.lock, an input value is either a string (a direct reference to a
    # node, i.e. the root declared its own input) or a list (a `follows` path).
    nixpkgs_input = root_inputs.get("nixpkgs")
    if isinstance(nixpkgs_input, list):
        if nixpkgs_input != ["platform", "nixpkgs"]:
            errors.append(
                f"root nixpkgs follows `{'/'.join(nixpkgs_input)}`, "
                "expected `platform/nixpkgs`"
            )
    elif isinstance(nixpkgs_input, str):
        errors.append(
            "root declares its own nixpkgs; use "
            '`nixpkgs.follows = "platform/nixpkgs"` instead'
        )

    # 3. approved hosts only
    for name, node in nodes.items():
        if name == "root":
            continue
        host, ref = node_url(node)
        if host not in APPROVED_HOSTS and host != "unknown":
            errors.append(f"input `{name}` resolves to unapproved host `{host}` ({ref})")

    if errors:
        print(f"flake.lock policy violations in {path}:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"{path}: ok")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
