# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12"]
# ///
"""Compare full process lifetime in interleaved batches separated by a pause."""
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

import typer


# Borrows paths/options through return; owns and waits for every child and its
# pipes. Owns samples locally; the caller owns the written JSON. Failures close
# pipes and leave no running child. Warmups are excluded from results.
def main(baseline: Path, candidate: Path, runs: int = 150,
         output: Path = Path("zig-out/startup-comparison.json")) -> None:
    if runs < 150:
        raise typer.BadParameter("use at least 150 runs per binary per batch")
    env = dict(os.environ)
    env.pop("V8_STARTUP_TRACE", None)
    binaries = {"baseline": str(baseline.resolve()), "candidate": str(candidate.resolve())}
    batches = []
    rng = random.Random(20261014)
    for batch in range(2):
        if batch:
            typer.echo("Waiting 5 seconds before the second batch...")
            time.sleep(5)
        for _ in range(5):
            for binary in binaries.values():
                subprocess.run([binary], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, env=env, check=True)
        samples = {name: [] for name in binaries}
        for _ in range(runs):
            order = list(binaries)
            rng.shuffle(order)
            for name in order:
                start = time.perf_counter_ns()
                subprocess.run([binaries[name]], stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                               env=env, check=True)
                samples[name].append(time.perf_counter_ns() - start)
        summary = {name: {"median_ns": statistics.median(values),
                          "mean_ns": statistics.mean(values),
                          "stdev_ns": statistics.stdev(values)}
                   for name, values in samples.items()}
        saving = summary["baseline"]["median_ns"] - summary["candidate"]["median_ns"]
        batches.append({"batch": batch + 1, "summary": summary, "saving_median_ns": saving,
                        "samples_ns": samples})
        typer.echo(f"Batch {batch + 1}: {runs} runs per binary")
        for name, values in summary.items():
            typer.echo(f"  {name}: median {values['median_ns']/1e6:.3f} ms, "
                       f"mean {values['mean_ns']/1e6:.3f} ± {values['stdev_ns']/1e6:.3f} ms")
        typer.echo(f"  Candidate median saving: {saving/1e6:+.3f} ms")
    output.write_text(json.dumps({"binaries": binaries, "runs_per_batch": runs,
                                  "pause_seconds": 5, "batches": batches}, indent=2) + "\n")
    typer.echo(f"Raw results: {output}")


if __name__ == "__main__":
    typer.run(main)
