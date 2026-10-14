# Build the shell
build-shell_darwin mode="debug":
    zig build-exe \
      ./src/shell.zig \
      {{if mode == "release" { "-O small" } else if mode == "debug" { "-O debug" } else { error("mode must be debug or release") }}} \
      -I./src -lv8_zig -L./zig-out -lmimalloc -L./zig-out/lib \
      -lc -lc++ \
      -freference-trace=7 \
      -femit-bin=./zig-out/shell

SDK := "-Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

# Build and install libraries; pass `release` for V8 .fast and mimalloc .safe.
build-lib_darwin mode="debug":
    zig build {{SDK}} {{if mode == "release" { "-Doptimize=safe" } else if mode == "debug" { "" } else { error("mode must be debug or release") }}}
