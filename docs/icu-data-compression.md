# ICU data compression feasibility

Research date: 2026-10-14. Inspected the pinned V8 15.2.124.1 tree, which contains ICU 78.2.

## Implemented size-focused path

The build now embeds the entire original package as one zstd level-19 frame,
including content size and checksum. The generator verifies a byte-for-byte
round trip. It retains every original locale and feature; no filtering or lazy
per-item loading is implemented.

`build/zstd.build.zig` compiles only common and decompression sources from pinned
zstd 1.5.7, using Zig `.small`, stripped debug information, no legacy support or
assembly, and upstream size options (`HUF_FORCE_DECOMPRESS_X1`,
`ZSTD_FORCE_DECOMPRESS_SEQUENCES_SHORT`, `ZSTD_NO_INLINE`,
`ZSTD_STRIP_ERROR_STRINGS`, `ZSTD_NO_UNUSED_FUNCTIONS`, `DYNAMIC_BMI2=0`).
The decoder archive is 71,520 bytes on the measured macOS arm64 build; this is
the archive size, not its final executable contribution. Its decoder expanded
the real ICU frame and matched every byte in an independent C smoke check.
See [upstream size-reduction guidance](https://github.com/facebook/zstd/blob/v1.5.7/lib/README.md).

The compressed payload is 3,808,080 bytes versus 10,822,192 original bytes:
64.8% smaller, before accounting for decoder and registration overhead.
The Zig build flattens the decoder archive into `libv8_zig.a`. GN builds the
binding/loader and data array, but does not build zstd. `zig build build-zstd`
also installs the decoder alone for inspection. Python compression dependencies
are pinned in `build-tools/scripts/compress-icu.py` and run via uv.

The binding registers a lazy provider and disables external data files before
V8 initialization. Both `V8.initialize` and `V8.initializeICU` leave the package
compressed. The first actual ICU common-data request expands the whole package,
verifies its length, and registers a 16-byte-aligned immutable buffer through
`udata_setCommonData`. ICU borrows this host-owned buffer until process exit.
Later requests reuse it. This defers the whole package; it does not implement
per-item decompression.

`build-tools/patches/icu/0001-lazy-data.patch` adds the provider hook to the pinned ICU
checkout. The build applies it separately from the V8 patches. ICU invokes the
provider before acquiring its data-cache mutex; thread-safe static initialization
serializes concurrent first requests and caches success or failure. Allocation,
decompression, or registration failure releases unpublished storage and reports
an ICU error at use. `initializeICU` reports only provider-configuration success.
Do not call ICU cleanup or reinitialize after registering the provider.

No external data file is required at runtime. The build-time snapshot generator
does not register this provider and continues using the original raw package.
Prebuilt archives must include the patched ICU loader and matching binding.
`zig build test-icu-lazy` runs a separate-process test verifying that startup and
plain JS leave data compressed, followed by concurrent multilingual first use.

### Measured result and verification

The release shell decreased from 53,468,808 bytes (50.99 MiB) to 46,617,240
bytes (44.46 MiB): 6,851,568 bytes (6.53 MiB, 12.81%) smaller. Temporary stripped
copies decreased from 39,647,392 to 32,750,024 bytes. These compare the saved
pre-compression executable with the current executable; intrinsic graph changes
were being developed in parallel, so the whole-executable difference is not an
isolated measurement of decoder overhead. The original/compressed ICU payload
sizes above are a direct comparison of the same data bytes.

Verified that GN's archive contains no zstd implementation, while the final
bundled archive contains the Zig decoder and no compressor/dictionary-training
symbols. The shell's embedded ICU data symbol is now the small stub; the real
data is stored in `v8_zig_icu_compressed`. The shell ran successfully and produced
the same multilingual formatting/Thai segmentation output as the saved binary.
All three focused ICU tests passed, including idempotent initialization and
multilingual service coverage. Formatting and whitespace checks passed.

Deferred loading keeps the ICU package compressed through V8 initialization,
context creation and plain JavaScript execution. First actual ICU data use pays
the expansion cost. The isolated concurrent-first-use test checks this behavior;
see [startup measurement guidance](shell-performance.md#startup-tracing) for
measuring the current shell.

Yes: ICU data can be filtered and compressed. Per-item lazy decompression with a shared zstd dictionary is feasible, but requires a custom ICU loader change; it is not an existing public ICU configuration switch. Compressing data does not compress ICU's native machine code.

## Filtering

ICU's supported Data Build Tool slices locales, whole feature files, and individual resource-bundle entries. It needs the original data sources; a prebuilt `.dat` can bypass filter rules. This project's Chromium/V8 vendored ICU data-generation pipeline must consume a rebuilt package, rather than merely setting `ICU_DATA_FILTER_FILE` during the Zig build. [ICU Data Build Tool](https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html).

Removing locales changes the available `Intl` locale set and fallback behavior. Removing collation, calendar, numbering, timezone, or segmentation resources can change results or cause construction failures. A startup trace alone cannot define an unused-data list for a general-purpose JavaScript shell: later user programs may request it. Choose an explicit supported locale/feature policy and test its behavior.

## Compression designs

1. **Whole-package decompression:** embed a compressed `.dat`, decompress it into aligned storage, then call `udata_setCommonData` before ICU/V8 initialization. This uses public ICU APIs and preserves the data if the original package is reproduced exactly. It allocates the full expanded package and adds startup decompression work.
2. **Per-item decompression:** build an index from ICU item names to individually compressed frames and sizes. At first lookup, decompress the requested item into aligned stable storage, validate it, cache it, and return its address to ICU. This requires modifying the internal data-loading path or implementing a new internal package format. Preserve resource aliases, parent fallbacks, pool bundles, and dependent items; do not assume each locale is independent.

The local `source/common/udata.cpp` calls the internal `pCommonData->vFuncs->Lookup` from `doLoadFromCommonData`, then passes the resulting `DataHeader*` to `checkDataItem`. That is a potential patch boundary. The public `udata_openChoice` callback only accepts or rejects data already loaded; it does not supply bytes. Public `udata_setCommonData` supplies an uncompressed package image, not an arbitrary per-item loader. [ICU 77 udata API](https://github.com/unicode-org/icu/blob/release-77-1/icu4c/source/common/unicode/udata.h), [ICU 77 loading implementation](https://github.com/unicode-org/icu/blob/release-77-1/icu4c/source/common/udata.cpp).

ICU data requires at least 8-byte alignment, preferably 16. Caller-provided common data remains caller-owned. A custom cache must keep expanded bytes immutable and at stable addresses for all readers; conservatively retain them until all V8/ICU users are gone and ICU cleanup has completed, or until process exit. Closing an individual wrapper does not prove that cached ICU objects no longer retain pointers. Synchronize concurrent first loads, handle allocation/decompression failure, and bound/check lengths before publishing entries. [ICU data API](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/udata_8h.html), [ICU data management](https://unicode-org.github.io/icu/userguide/icu_data/).

A trained zstd dictionary can improve compression of small related items. Independently addressable frames still need an external item index. Measure dictionaries trained on the actual retained ICU item corpus; compare dictionary overhead, decoder code, index size, padding, per-frame overhead, and expanded cache memory. Shared prepared dictionaries can avoid repeatedly preparing dictionary tables. No compression ratio has been measured here. [zstd project and dictionary description](https://github.com/facebook/zstd), [zstd API](https://github.com/facebook/zstd/blob/dev/lib/zstd.h).

## Expected impact for this shell

The measured ICU data payload is approximately 10.32 MiB. Compression can reduce stored binary size, but is not established as a startup optimization. Uncompressed executable data is already demand-paged by the operating system; unused pages need not be faulted in. Lazy decompression adds CPU, allocation, and synchronization to first access, and dirty expanded heap pages can increase resident memory compared with file-backed pages.

The measured first `Intl.Segmenter` hardening block costs approximately 7.94 ms. A compressed loader still has to expand any data that block requests. Investigate what this construction loads and whether the hardening can avoid eager expensive initialization before expecting compression to reduce startup time. Keep filtering, compressed package size, cold startup, warm startup, first Intl use, and peak/steady resident memory as separate measurements.
