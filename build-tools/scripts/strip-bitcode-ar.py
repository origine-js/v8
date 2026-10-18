#!/usr/bin/env python3
"""Copy static archives without their LLVM bitcode members.

usage: strip-bitcode-ar.py <llvm-ar> <out-dir> <archive>...

For each archive, prints the path to link in its place, one per line and in order: the archive
itself when it has no bitcode member, otherwise a copy under <out-dir> that keeps only the
native members (non-object members such as rustc's lib.rmeta are dropped as well).

lto-clang.sh uses this for its second link, where the bitcode has already been compiled to
native objects: an archive's bitcode members would otherwise be loaded again to satisfy a
symbol the LTO output leaves to a native member, and clash with those objects.

Ownership: borrows the archives (read only); owns <out-dir>, which must exist and be empty.
Standard library only, BSD-format (Apple) archives.
"""
import os
import subprocess
import sys

BITCODE_MAGICS = (b"BC\xc0\xde", b"\xde\xc0\x17\x0b")  # plain, and Apple's wrapper
MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe")


def members(data):
    """Yield (name, body) for each real member of the BSD ar archive in `data`."""
    assert data[:8] == b"!<arch>\n", "not an ar archive"
    pos = 8
    while pos < len(data):
        hdr = data[pos : pos + 60]
        pos += 60
        name = hdr[:16].decode().strip()
        size = int(hdr[48:58])
        body = data[pos : pos + size]
        pos += size + (size & 1)
        if name.startswith("#1/"):  # BSD long name: stored at the start of the body
            n = int(name[3:])
            name, body = body[:n].rstrip(b"\0").decode(), body[n:]
        if name.startswith("__.SYMDEF") or name in ("/", "//"):
            continue
        yield name, body


def strip(llvm_ar, archive, work):
    """Return the path of a bitcode-free equivalent of `archive`, written under `work`."""
    with open(archive, "rb") as f:
        data = f.read()
    native, has_bitcode = [], False
    for name, body in members(data):
        if body[:4] in BITCODE_MAGICS:
            has_bitcode = True
        elif body[:4] in MACHO_MAGICS:
            native.append(body)
    if not has_bitcode:
        return archive
    os.makedirs(work)
    files = []
    for i, body in enumerate(native):  # numbered: member names repeat within one archive
        path = os.path.join(work, f"{i}.o")
        with open(path, "wb") as f:
            f.write(body)
        files.append(path)
    out = work + ".a"
    if files:
        subprocess.run([llvm_ar, "--format=darwin", "rcs", out, *files], check=True)
    else:
        with open(out, "wb") as f:
            f.write(b"!<arch>\n")
    for path in files:
        os.remove(path)
    os.rmdir(work)
    return out


def main(argv):
    llvm_ar, out_dir, archives = argv[1], argv[2], argv[3:]
    for i, archive in enumerate(archives):
        print(strip(llvm_ar, archive, os.path.join(out_dir, f"ar{i}")))


if __name__ == "__main__":
    main(sys.argv)
