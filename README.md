# zig-v8

Builds V8 from official source and provides C bindings and a Zig API. This would be used for embedding the V8 runtime into your Zig or C ABI compatible projects.

V8 is the JavaScript runtime that powers Google Chrome.

## System Requirements
- Zig 0.17.0. Download from https://ziglang.org/download/.
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
zig build
```

If V8 fails to compile against your newest macOS SDK (e.g. ICU: `use of undeclared identifier 'NAN'`), point it at an older one with
`-Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.

Once complete, you can find v8 in: `zig-out/libv8_zig.a`

`zig build gen` writes the generated struct sizes to `zig-out/binding.zig`; merge it into `src/binding.zig` by hand.
