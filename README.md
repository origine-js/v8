# zig-v8

Builds V8 from official source and provides C bindings and a Zig API. This would be used for embedding the V8 runtime into your Zig or C ABI compatible projects.

V8 is the JavaScript runtime that powers Google Chrome.

## System Requirements
- Zig (0.16.0-dev, https://codeberg.org/ziglang/zig). Download from https://ziglang.org/download/.
- Python 3 (2.7 seems to work as well)
- unzip
- rsync
- For native macOS builds:
  - XCode (You won't need this when using zig's c++ toolchain!)<br/>
if you come across this error:<br />
`xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`<br />
  run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Build
Compiling v8 will take 20+ minutes.

```sh
zig build gen
```

Once complete, you can find v8 in: `zig-out/libv8_zig.a`
