#!/usr/bin/env python3
# /// script
# dependencies = ["typer"]
# ///
"""Rewrite a ThinLTO bitcode static archive as a native Mach-O archive.

usage: uv run --script native-archive.py <in.a> <out.a> <v8-clang-bin-dir> [--target TRIPLE]

Zig's Mach-O linker cannot read LLVM bitcode. Each bitcode member is compiled on its own with
V8's matching clang, not linked whole-program, so no hidden-visibility symbol (vtables, shim
helpers) is internalized and dropped. Native members are copied through unchanged.

Ownership: borrows <in.a> (read only); replaces <out.a> atomically, so a failed run leaves any
previous <out.a> untouched; owns <out.a>.work, which is wiped, recreated and removed on success.
A no-op when <out.a> is already newer than <in.a>. Run it from any directory.
"""
import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from typing import Annotated

import typer

# Oldest macOS the generated objects target. Sequoia 15 or newer.
MACOS_TARGET = "arm64-apple-macos15.0"
BITCODE_MAGICS = (b"BC\xc0\xde", b"\xde\xc0\x17\x0b")  # plain, and Apple's wrapper


def split_archive(path, bc_dir, nat_dir):
    """Write each member of the BSD ar archive at `path` to `bc_dir` (bitcode) or `nat_dir`
    (everything else) under a unique numeric name, since `ar x` would collapse members that
    share a basename. Borrows `path`; the caller owns the written files. Returns the paths of
    the bitcode files."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"!<arch>\n", "not an ar archive"
    pos, idx, bitcode = 8, 0, []
    while pos < len(data):
        hdr = data[pos : pos + 60]
        pos += 60
        name = hdr[:16].decode().strip()
        size = int(hdr[48:58])
        body = data[pos : pos + size]
        if name.startswith("#1/"):  # BSD long name: stored at the start of the body
            n = int(name[3:])
            name = body[:n].rstrip(b"\0").decode()
            body = body[n:]
        pos += size + (size & 1)
        if name.startswith("__.SYMDEF") or name in ("/", "//"):
            continue
        if body[:4] in BITCODE_MAGICS:
            out = os.path.join(bc_dir, f"{idx}.bc")
            bitcode.append(out)
        else:
            out = os.path.join(nat_dir, f"{idx}.o")
        with open(out, "wb") as f:
            f.write(body)
        idx += 1
    return bitcode


def compile_member(clang, bc_path, target):
    """Compile the bitcode file `bc_path` to `<bc_path minus .bc>.o` beside it with the clang
    binary `clang` for `target`. Borrows all arguments through return; returns an owned
    output path and raises CalledProcessError on failure."""
    subprocess.run(
        [clang, "-c", "-O2", "-x", "ir", "-target", target, "-Wno-override-module",
         bc_path, "-o", bc_path[:-3] + ".o"],
        check=True,
    )
    return bc_path[:-3] + ".o"


def main(
    src: Annotated[str, typer.Argument()],
    out: Annotated[str, typer.Argument()],
    clang_dir: Annotated[str, typer.Argument()],
    target: Annotated[str, typer.Option()] = MACOS_TARGET,
):
    """Borrows input paths through return; owns out and temporary out.work storage.

    Atomically replaces out on success; a failure preserves any previous archive.
    Temporary storage is retained on failure for diagnosis and removed on success.
    """
    work = out + ".work"
    if os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(src):
        return
    shutil.rmtree(work, ignore_errors=True)
    bc_dir, nat_dir = os.path.join(work, "bc"), os.path.join(work, "nat")
    os.makedirs(bc_dir)
    os.makedirs(nat_dir)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)

    bitcode = split_archive(src, bc_dir, nat_dir)
    clang = os.path.join(clang_dir, "clang")
    with ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
        # Borrows each path and compiler configuration until the pool joins;
        # returns a caller-owned output path or propagates compilation failure.
        objects = list(pool.map(lambda p: compile_member(clang, p, target), bitcode))
    objects += sorted(os.path.join(nat_dir, n) for n in os.listdir(nat_dir))

    tmp = out + ".tmp"
    # Pass the list in a file: ~2400 paths can approach the argument-length limit.
    with open(os.path.join(work, "objects.txt"), "w") as f:
        f.write("\n".join(objects) + "\n")
    subprocess.run(
        ["libtool", "-static", "-no_warning_for_no_symbols", "-filelist",
         os.path.join(work, "objects.txt"), "-o", tmp],
        check=True,
    )
    os.replace(tmp, out)
    shutil.rmtree(work)


if __name__ == "__main__":
    typer.run(main)
