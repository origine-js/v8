v8_version := "15.2.124.1"
out := "zig-out"
lld := justfile_directory() / ".lp-cache/v8-" + v8_version + "/third_party/llvm-build/Release+Asserts/bin/ld64.lld"

# GN options of the release V8: ThinLTO bitcode (linked by ld64.lld below) and no C++ unwind tables.
# Temporal and runtime call stats stay on; they are the defaults.
release_lib_flags := "-Doptimize=safe -Dthin_lto=true -Dexclude_unwind_tables=true"

default:
    @just --list

# Build the shell; pass `release` for the ReleaseSmall, LTO, ICF-folded binary.
# Both modes link zig-out/libv8_zig.a, so run `build-lib_darwin <same mode>` first.
build-shell_darwin mode="debug":
    @{{just_executable()}} --justfile {{justfile()}} _shell_{{ if mode == "release" { "release" } else if mode == "debug" { "debug" } else { error("mode must be debug or release") } }}

# Build and install libraries; pass `release` for V8 .fast (ThinLTO), mimalloc .safe.
build-lib_darwin mode="debug":
    zig build {{ if mode == "release" { release_lib_flags } else if mode == "debug" { "" } else { error("mode must be debug or release") } }}

# Debug shell: Zig's own linker against the unoptimised libraries.
[private]
_shell_debug:
    zig build-exe ./src/shell.zig -O Debug -I./src \
      -lv8_zig -L./{{out}} -lmimalloc -L./{{out}}/lib -lc -lc++ \
      -freference-trace=7 \
      -femit-bin=./{{out}}/shell

# Release shell. It links with V8's ld64.lld instead of Zig's Mach-O linker because
#  - the ThinLTO V8 archive is bitcode, which Zig's linker cannot read, and
#  - Zig's linker has no identical-code folding (`--icf=all`) while Apple's ld folds
#    almost nothing in V8 (about 3 MB).
# `-enable-merge-functions` folds near-identical functions without touching inlining,
# so JS speed is unaffected. lld already ad-hoc signs the output.
[private]
_shell_release:
    zig build-obj ./src/shell.zig -O ReleaseSmall -I./src -lc \
      -freference-trace=7 \
      -femit-bin=./{{out}}/shell.o
    /usr/bin/clang++ -fuse-ld={{lld}} -o ./{{out}}/shell \
      ./{{out}}/shell.o ./{{out}}/libv8_zig.a ./{{out}}/lib/libmimalloc.a \
      -Wl,-dead_strip -Wl,--icf=all -Wl,-x -Wl,-w \
      -Wl,-mllvm,-enable-merge-functions
    rm -f ./{{out}}/shell.o
