#!/usr/bin/env python3
"""Convert a Nix closure listing into a minimal CycloneDX 1.5 document.

Stand-in for `flakebom`. Store paths look like:
    /nix/store/<32-char-hash>-<name>-<version>[-<output>]
Version detection is heuristic: the last dash-separated segment counts as a
version if it starts with a digit.
"""
import json
import re
import sys

STORE_RE = re.compile(r"^/nix/store/[a-z0-9]{32}-(?P<rest>.+)$")
KNOWN_OUTPUTS = {"bin", "dev", "lib", "man", "doc", "out", "info", "debug"}


def split_name_version(rest: str):
    """Split `<name>-<version>-<output>` the way nixpkgs conventionally forms it.

    The version is everything from the first dash-separated segment that starts
    with a digit, so `glibc-2.40-36` is glibc @ 2.40-36, not glibc-2.40 @ 36.
    """
    parts = rest.split("-")
    output = None
    if len(parts) > 1 and parts[-1] in KNOWN_OUTPUTS:
        output = parts.pop()

    version = None
    for i in range(1, len(parts)):
        if re.match(r"^[0-9]", parts[i]):
            version = "-".join(parts[i:])
            parts = parts[:i]
            break

    return "-".join(parts), version, output


def main(path: str) -> int:
    components = []
    seen = set()
    with open(path) as fh:
        for line in fh:
            store_path = line.strip()
            if not store_path:
                continue
            m = STORE_RE.match(store_path)
            if not m:
                continue
            name, version, output = split_name_version(m.group("rest"))
            key = (name, version)
            if key in seen:
                continue
            seen.add(key)
            components.append(
                {
                    "type": "library",
                    "name": name,
                    "version": version or "unknown",
                    "purl": f"pkg:nix/{name}@{version or 'unknown'}",
                    "properties": [
                        {"name": "nix:store_path", "value": store_path},
                        {"name": "nix:output", "value": output or "out"},
                    ],
                }
            )

    json.dump(
        {
            "bomFormat": "CycloneDX",
            "specVersion": "1.5",
            "version": 1,
            "metadata": {"tools": [{"name": "store-paths-to-cyclonedx"}]},
            "components": sorted(components, key=lambda c: c["name"]),
        },
        sys.stdout,
        indent=2,
    )
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
