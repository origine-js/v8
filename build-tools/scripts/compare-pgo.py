# /// script
# requires-python = ">=3.11"
# dependencies = ["typer>=0.12,<1"]
# ///
"""Compare mksnapshot's initial builtin graph hashes with a builtin PGO profile."""
import csv
from pathlib import Path
import re

import typer


# Borrows path through return, closes the file, and returns a caller-owned dict
# of copied names and unsigned 32-bit hashes. Read/parse failures retain nothing.
def read_hashes(path: Path) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^Builtin: ([^,]+), hash: 0x([0-9a-f]+)$", path.read_text(), re.MULTILINE
        )
    }


# Borrows paths through return; owns and releases parsed file contents. Prints
# copied diagnostics, retaining no resources on success or failed assertions.
def main(
    profile: Path,
    hashes: Path,
    compare: Path | None = None,
    expect_mismatches: int | None = None,
    expect_absent: int | None = None,
    expect_differences: int | None = None,
) -> None:
    if expect_differences is not None and compare is None:
        raise typer.BadParameter("--expect-differences requires --compare")
    with profile.open(newline="") as stream:
        expected = {
            row[1]: int(row[2]) & 0xFFFFFFFF
            for row in csv.reader(stream)
            if row and row[0] == "builtin_hash"
        }
    actual = read_hashes(hashes)
    if not expected or not actual:
        raise typer.BadParameter("profile and hash dump must both contain builtin hashes")
    common = expected.keys() & actual.keys()
    mismatches = sorted(name for name in common if expected[name] != actual[name])
    absent = sorted(expected.keys() - actual.keys())
    typer.echo(
        f"Profile records: {len(expected)}; matched: {len(common) - len(mismatches)}; "
        f"mismatched: {len(mismatches)}; absent: {len(absent)}"
    )
    for name in mismatches:
        typer.echo(f"{name}: profile={expected[name]:08x}, generated={actual[name]:08x}")
    if absent:
        typer.echo("Absent: " + ", ".join(absent))
    if compare is not None:
        other = read_hashes(compare)
        if not other:
            raise typer.BadParameter("comparison dump must contain builtin hashes")
        shared = common & other.keys()
        differences = sorted(name for name in shared if actual[name] != other[name])
        typer.echo(f"Compared builds: {len(shared)} shared profile entries; {len(differences)} hash differences")
        for name in differences:
            typer.echo(f"{name}: generated={actual[name]:08x}, comparison={other[name]:08x}")
        if expect_differences is not None and len(differences) != expect_differences:
            raise typer.Exit(1)
    if expect_mismatches is not None and len(mismatches) != expect_mismatches:
        raise typer.Exit(1)
    if expect_absent is not None and len(absent) != expect_absent:
        raise typer.Exit(1)


if __name__ == "__main__":
    typer.run(main)
