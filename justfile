build-shell_darwin:
    zig build-exe \
      ./src/shell.zig \
      -I./src -lv8_zig -L./zig-out \
      -lc -lc++ \
      -framework CoreFoundation -framework Security \
      -freference-trace=7 \
      -femit-bin=./zig-out/shell

SDK := "-Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

build-lib_darwin:
    zig build {{SDK}}
