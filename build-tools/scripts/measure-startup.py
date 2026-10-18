# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12"]
# ///
"""Measure warm shell startup stages and complete process lifetime."""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

import typer


# Borrows binary/options for the call; owns child processes and pipes until each
# child exits. Output files are caller-owned; failed children raise after cleanup.
def main(binary: Path = Path("zig-out/shell"), runs: int = 30, warmup: int = 3,
         output: Path = Path("zig-out/startup-measurements.json")) -> None:
    if runs < 1 or warmup < 0:
        raise typer.BadParameter("runs must be positive and warmup nonnegative")
    measurements: list[dict[str, int]] = []
    env = {**os.environ, "V8_STARTUP_TRACE": "1"}
    for index in range(warmup + runs):
        start = time.perf_counter_ns()
        with subprocess.Popen([str(binary.resolve())], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env=env) as child:
            assert child.stderr is not None
            ready = None
            lines = []
            for line in child.stderr:
                lines.append(line)
                if line.startswith("startup total:"):
                    ready = time.perf_counter_ns() - start
            stdout, trailing_stderr = child.communicate()
            stderr = "".join(lines) + trailing_stderr
            result = subprocess.CompletedProcess(child.args, child.returncode,
                                                 stdout, stderr)
            result.check_returncode()
        elapsed = time.perf_counter_ns() - start
        sample = {"process_total": elapsed}
        if ready is not None:
            sample.update(launch_to_initialized=ready, initialized_to_exit=elapsed - ready)
        occurrences: dict[str, int] = {}
        for kind, name, ns in re.findall(r"^(startup|scope_detail) (\w+): (\d+) ns$", result.stderr, re.M):
            key = name if kind == "startup" else f"scope.{name}"
            occurrences[key] = occurrences.get(key, 0) + 1
            if kind == "scope_detail":
                key += f".{occurrences[key]}"
            sample[key] = int(ns)
        if "total" not in sample:
            raise RuntimeError("binary lacks V8_STARTUP_TRACE instrumentation")
        if index >= warmup:
            measurements.append(sample)
    medians = {key: statistics.median(row[key] for row in measurements)
               for key in measurements[0]}
    output.write_text(json.dumps({"runs": runs, "warmup": warmup,
                                 "median_ns": medians, "samples": measurements}, indent=2) + "\n")
    for name, ns in medians.items():
        typer.echo(f"{name:32s} {ns / 1e6:9.3f} ms")
    typer.echo(f"Raw samples: {output}")


if __name__ == "__main__":
    typer.run(main)
