# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12,<1"]
# ///
"""Prepare the validated macOS arm64 overlay without rewriting Google's baseline."""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

import typer


# Borrows text through return; returns an owned map of copied GN assignments.
def assignments(text: str) -> dict[str, str]:
    return dict(re.findall(r"(?m)^([a-zA-Z_][a-zA-Z_0-9]*)\s*=\s*(.+)$", text))


# Borrows destination/data through return. Atomically publishes cache-owned bytes
# using a unique temporary file; failure removes the temporary and preserves the
# prior destination. Identical content preserves the destination's mtime.
def publish(destination: Path, data: bytes) -> None:
    if destination.is_file() and destination.read_bytes() == data:
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.replace(destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


# Borrows paths/arguments through return; closes all inputs. Publishes a separate
# merged cache file and integrity receipt. Failure leaves Google's baseline and
# the checked-in measured profile unchanged; retains no handles or processes.
def main(checkout: Path, custom: Path, gn_args: str = typer.Option(...)) -> None:
    manifest = json.loads((custom / "manifest.json").read_text())
    actual = assignments(gn_args)
    if (actual.get("target_os") != '"mac"' or actual.get("v8_target_cpu") != '"arm64"'
            or actual.get("v8_zig_custom_builtin_pgo") != "true"):
        raise RuntimeError("custom builtin PGO is supported only for macOS arm64")
    expected = assignments(manifest["production_args"])
    for key in ("v8_builtins_profiling_log_file", "v8_zig_custom_builtin_pgo"):
        expected.pop(key, None)
        actual.pop(key, None)
    if actual != expected:
        raise RuntimeError("custom PGO configuration differs from training; regenerate or use -Dbuiltin_pgo=false")
    header = (checkout / "include/v8-version.h").read_text()
    version = ".".join(re.search(rf"#define V8_{field} (\d+)", header)[1] for field in
                       ("MAJOR_VERSION", "MINOR_VERSION", "BUILD_NUMBER", "PATCH_LEVEL"))
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if (manifest["version"] != version or manifest["revision"] != revision
            or manifest["target_os"] != "mac" or manifest["target_cpu"] != "arm64"):
        raise RuntimeError("custom PGO target or source revision differs from this build")
    if hashlib.sha256((checkout / "zig/.gn").read_bytes()).hexdigest() != manifest["dotfile_sha256"]:
        raise RuntimeError("embedder GN defaults differ from PGO training; regenerate the profile")
    measured = (custom / "builtins.profile").read_bytes()
    if hashlib.sha256(measured).hexdigest() != manifest["profile_sha256"]:
        raise RuntimeError("custom builtin profile failed its SHA-256 check")
    rows = list(csv.reader(measured.decode().splitlines()))
    names = set(manifest["builtins"])
    hashes = {row[1]: int(row[2]) & 0xFFFFFFFF for row in rows if row[0] == "builtin_hash"}
    if len(names) != 16 or set(hashes) != names or any(row[1] not in names for row in rows):
        raise RuntimeError("custom profile must contain exactly the 16 measured builtins")
    for name in names:
        entry = manifest["builtins"][name]
        if hashes[name] != int(entry["hash"], 16) or entry["entry_count"] <= 0 or entry["branch_hints"] <= 0:
            raise RuntimeError(f"missing measured coverage or hash mismatch for {name}")
    directory = checkout / "tools/builtins-pgo/profiles"
    google = (directory / "x64.profile").read_bytes()
    receipt = json.loads((directory / "google-x64.json").read_text())
    google_sha = hashlib.sha256(google).hexdigest()
    if receipt["version"] != version or receipt["revision"] != revision or receipt["sha256"] != google_sha:
        raise RuntimeError("Google baseline failed its integrity or source-revision check")
    kept = [line for line in google.decode().splitlines() if line.split(",")[1] not in names]
    combined = ("\n".join(kept) + "\n").encode() + measured
    destination = directory / "origine-mac-arm64.profile"
    publish(destination, combined)
    merged_receipt = {
        "version": version, "revision": revision, "target_os": "mac", "target_cpu": "arm64",
        "google_sha256": google_sha, "custom_sha256": manifest["profile_sha256"],
        "combined_sha256": hashlib.sha256(combined).hexdigest(), "custom_builtins": sorted(names),
        "builtin_reordering": False,
    }
    publish(directory / "origine-mac-arm64.json", (json.dumps(merged_receipt, indent=2, sort_keys=True) + "\n").encode())
    typer.echo("macOS arm64 PGO: Google baseline plus 16 measured configuration-matched profiles")


if __name__ == "__main__":
    typer.run(main)
