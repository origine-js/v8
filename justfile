build-shell_darwin:
    zig build-exe ./src/shell.zig -I./src -lv8_zig -L./zig-out -lc -lc++ -framework CoreFoundation -framework Security
