# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12,<1"]
# ///
"""Train and validate a separate builtin-PGO profile; never enables it in production."""
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import typer


TARGETS = (
    "RunMicrotasks", "AsyncFunctionEnter", "AsyncFunctionAwait",
    "AsyncGeneratorYieldWithAwait", "AsyncGeneratorReturn",
    "AsyncGeneratorPrototypeNext", "AsyncGeneratorPrototypeReturn",
    "AsyncGeneratorAwait", "FulfillPromise", "RejectPromise",
    "NewPromiseCapability", "PromiseReject", "PromiseConstructor",
    "PromiseResolve", "PromisePrototypeThen", "CreateTypedArray",
)


# Borrows path through return; closes the input and returns a copied digest.
def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# Borrows command/cwd until child completion; owns and closes its log. Failure
# raises with the log path and retains no process or open file descriptor.
def run(command: list[str], cwd: Path, log: Path) -> None:
    typer.echo(f"Running {command[0]} (log: {log})")
    environment = os.environ.copy()
    environment["PATH"] = str(Path(command[0]).parent) + os.pathsep + environment.get("PATH", "")
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=cwd, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}); see {log}")


# Borrows source and replacement strings through return; returns owned GN text.
def replace_arg(source: str, name: str, value: str) -> str:
    pattern = rf"(?m)^{re.escape(name)}\s*=.*$"
    if re.search(pattern, source):
        return re.sub(pattern, f"{name} = {value}", source)
    return source + f"{name} = {value}\n"


# Borrows input paths through return. Build/cache and destination own published
# files; each run owns persistent logs beneath the training cache. Child processes
# finish before files close. Existing validated profiles survive failed runs.
def main(
    checkout: Path,
    production: Path,
    destination: Path,
    iterations: int = typer.Option(8000, min=1000),
    jobs: int = typer.Option(16, min=1),
    strict_reader: Path | None = None,
) -> None:
    checkout = checkout.resolve()
    production = production.resolve()
    destination = destination.resolve()
    tools_root = Path(__file__).resolve().parents[1]
    workload = tools_root / "pgo/train.js"
    baseline_args = (production / "args.gn").read_text()
    os_match = re.search(r'^target_os\s*=\s*"([^"]+)"', baseline_args, re.MULTILINE)
    cpu_match = re.search(r'^v8_target_cpu\s*=\s*"([^"]+)"', baseline_args, re.MULTILINE)
    if not os_match or not cpu_match:
        raise typer.BadParameter("production args.gn must name target_os and v8_target_cpu")
    target_os, target_cpu = os_match[1], cpu_match[1]
    training = checkout / f"out/{target_os}-{target_cpu}-builtin-pgo-training"
    training.mkdir(parents=True, exist_ok=True)
    args = baseline_args
    for name, value in {
        "v8_enable_builtins_profiling": "true",
        "v8_builtins_profiling_log_file": '""',
        "v8_enable_builtins_reordering": "false",
    }.items():
        args = replace_arg(args, name, value)
    (training / "args.gn").write_text(args)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=training))
    depot = checkout.parent / checkout.name.replace("v8-", "depot_tools-", 1)
    run([str(depot / "gn"), "--root=.", "--dotfile=zig/.gn", "gen", str(training)],
        checkout, run_dir / "gn.log")
    run([str(depot / "autoninja"), "-C", str(training), f"-j{jobs}", "d8"],
        checkout, run_dir / "build.log")
    counters = run_dir / "counters.log"
    run([str(training / "d8"), f"--turbo-profiling-output={counters}",
         str(workload), "--", str(iterations)], checkout, run_dir / "workload.log")
    entries = {name: 0 for name in TARGETS}
    for line in counters.read_text().splitlines():
        fields = line.split("\t")
        if fields[0] == "block" and fields[1] in entries and fields[2] == "0":
            entries[fields[1]] += int(fields[3])
    missing = [name for name, count in entries.items() if count == 0]
    if missing:
        raise RuntimeError(f"workload did not execute: {', '.join(missing)}; see {run_dir}")
    full_profile = run_dir / "all-builtins.profile"
    run([sys.executable, str(checkout / "tools/builtins-pgo/get_hints.py"),
         "--min", "1000", "--ratio", "40", str(counters), str(full_profile)],
        checkout, run_dir / "hints.log")
    selected = run_dir / "builtins.profile"
    rows = list(csv.reader(full_profile.read_text().splitlines()))
    rows = [row for row in rows if len(row) > 1 and row[1] in TARGETS]
    with selected.open("w", newline="") as stream:
        csv.writer(stream, lineterminator="\n").writerows(rows)
    recorded = {row[1]: int(row[2]) & 0xFFFFFFFF for row in rows if row[0] == "builtin_hash"}
    if set(recorded) != set(TARGETS):
        raise RuntimeError("profile is missing hashes for requested builtins")
    hashes = run_dir / "production-hashes.txt"
    run([str(production / "mksnapshot"), f"--target_os={target_os}",
         f"--target_arch={target_cpu}", "--predictable", "--no-use-ic",
         "--turbo-elide-frames", "--random-seed=314159265",
         f"--dump-builtins-hashes-to-file={hashes}",
         f"--embedded_src={run_dir / 'validation.S'}",
         f"--startup_src={run_dir / 'validation.cc'}"],
        checkout, run_dir / "validate-snapshot.log")
    expected = {name: int(value, 16) for name, value in re.findall(
        r"^Builtin: ([^,]+), hash: 0x([0-9a-f]+)$", hashes.read_text(), re.MULTILINE)}
    mismatches = [name for name in TARGETS if expected.get(name) != recorded[name]]
    if mismatches:
        raise RuntimeError(f"training/production graph mismatch: {', '.join(mismatches)}")
    strict_validation = None
    if strict_reader is not None:
        strict_reader = strict_reader.resolve()
        strict_log = run_dir / "strict-reader.log"
        run([str(strict_reader), f"--target_os={target_os}", f"--target_arch={target_cpu}",
             "--predictable", "--no-use-ic", "--turbo-elide-frames", "--random-seed=314159265",
             f"--turbo-profiling-input={selected}", "--abort-on-bad-builtin-profile-data",
             "--warn-about-builtin-profile-data",
             f"--embedded_src={run_dir / 'strict-validation.S'}",
             f"--startup_src={run_dir / 'strict-validation.cc'}"],
            checkout, strict_log)
        if "Ignoring builtin PGO" in strict_log.read_text():
            raise RuntimeError("strict reader excluded profiles instead of validating them")
        strict_validation = {
            "result": "accepted with --abort-on-bad-builtin-profile-data; no profiles ignored",
            "mksnapshot_sha256": digest(strict_reader),
        }
    header = (checkout / "include/v8-version.h").read_text()
    version = ".".join(re.search(rf"#define V8_{field} (\d+)", header)[1] for field in
                       ("MAJOR_VERSION", "MINOR_VERSION", "BUILD_NUMBER", "PATCH_LEVEL"))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
    source_diff = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=checkout)
    summary = {
        name: {
            "hash": f"{recorded[name]:08x}",
            "entry_count": entries[name],
            "branch_hints": sum(row[0] == "block_hint" and row[1] == name for row in rows),
            "executed_blocks": sum(row[0] == "block" and row[1] == name for row in rows),
        } for name in TARGETS
    }
    manifest = {
        "version": version, "revision": revision,
        "target_os": target_os, "target_cpu": target_cpu,
        "profile_sha256": digest(selected), "workload_sha256": digest(workload),
        "generator_sha256": digest(Path(__file__)),
        "hints_generator_sha256": digest(checkout / "tools/builtins-pgo/get_hints.py"),
        "raw_counters_sha256": digest(counters),
        "v8_source_diff_sha256": hashlib.sha256(source_diff).hexdigest(),
        "dotfile_sha256": digest(checkout / "zig/.gn"),
        "production_args": baseline_args, "training_args": args,
        "training_d8_sha256": digest(training / "d8"),
        "production_mksnapshot_sha256": digest(production / "mksnapshot"),
        "iterations_per_phase": iterations,
        "hint_min_count": 1000, "hint_ratio": 40,
        "workload_result": (run_dir / "workload.log").read_text(),
        "validation": "all 16 hashes match production initial graphs",
        "strict_reader_validation": strict_validation,
        "production_enabled": False,
        "scope": "focused synthetic workload; no performance improvement claimed",
        "builtins": summary,
    }
    compressed_counters = gzip.compress(counters.read_bytes(), mtime=0)
    manifest["counters_gzip_sha256"] = hashlib.sha256(compressed_counters).hexdigest()
    destination.mkdir(parents=True, exist_ok=True)
    # Each file replaces atomically; the manifest's digest detects an interrupted pair.
    temporary = destination / "builtins.profile.tmp"
    temporary.write_bytes(selected.read_bytes())
    temporary.replace(destination / "builtins.profile")
    temporary = destination / "counters.log.gz.tmp"
    temporary.write_bytes(compressed_counters)
    temporary.replace(destination / "counters.log.gz")
    temporary = destination / "manifest.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    temporary.replace(destination / "manifest.json")
    typer.echo(f"Validated profiles for all {len(TARGETS)} builtins: {destination}")
    typer.echo(f"Raw counters and logs: {run_dir}")
    typer.echo("Production exclusions remain enabled.")


if __name__ == "__main__":
    typer.run(main)
