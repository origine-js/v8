# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12,<1"]
# ///
"""Fetch Google's unmodified builtin profile for the exact source revision."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.request import urlopen

import typer


# Borrows checkout/profile through return. Publishes cache-owned files atomically;
# failed downloads leave existing validated profiles intact and release temporary bytes.
def main(checkout: Path, profile: str) -> None:
    if profile not in {"x64", "x86", "x64-rl", "x86-rl"}:
        raise typer.BadParameter("unsupported Google builtin profile")
    header = (checkout / "include/v8-version.h").read_text()
    fields = ["MAJOR_VERSION", "MINOR_VERSION", "BUILD_NUMBER", "PATCH_LEVEL"]
    version = ".".join(re.search(rf"#define V8_{field} (\d+)", header)[1] for field in fields)
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    directory = checkout / "tools/builtins-pgo/profiles"
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{profile}.profile"
    receipt = directory / f"google-{profile}.json"
    if receipt.is_file() and destination.is_file():
        cached = json.loads(receipt.read_text())
        if (cached.get("version") == version and cached.get("revision") == revision
                and cached.get("sha256") == hashlib.sha256(destination.read_bytes()).hexdigest()):
            typer.echo(f"Google builtin PGO: {version}, {profile}, verified cached profile")
            return
    base = f"https://storage.googleapis.com/chromium-v8-builtins-pgo/by-version/{version}"
    with urlopen(f"{base}/meta.json", timeout=120) as response:
        metadata = json.load(response)
    if metadata.get("version") != version or metadata.get("revision") != revision:
        raise RuntimeError("Google PGO metadata does not match the pinned V8 source")
    if profile not in metadata.get("profile", []):
        raise RuntimeError(f"Google did not publish {profile} for {version}")
    with urlopen(f"{base}/{profile}.profile", timeout=120) as response:
        data = response.read()
    if not data or b"builtin_hash," not in data:
        raise RuntimeError("downloaded builtin profile is empty or malformed")
    temporary = destination.with_suffix(".tmp")
    temporary.write_bytes(data)
    temporary.replace(destination)
    metadata["sha256"] = hashlib.sha256(data).hexdigest()
    temporary = receipt.with_suffix(".tmp")
    temporary.write_text(json.dumps(metadata, sort_keys=True) + "\n")
    temporary.replace(receipt)
    typer.echo(f"Google builtin PGO: {version}, {profile}, {len(data):,} bytes, sha256={metadata['sha256']}")


if __name__ == "__main__":
    typer.run(main)
