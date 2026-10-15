# Reproduction

shell-startup.patch exports the consolidated source delta from cfc7374 to
b0af166. It includes the existing runtime, V8 hardening and compressed/lazy ICU
changes needed by this build. Dependency caches under zig-pkg are excluded;
Zig fetches dependencies pinned in build.zig.zon.

Apply the patch in a checkout of cfc7374 using git apply --check followed by
git apply. The current checkout already contains these changes. Then run:

    just build-lib_darwin release
    just build-shell_darwin release

Tested on macOS arm64 with Zig 0.17.0 and the macOS 26.5 SDK configured in
justfile. The build applies upstream patches without manual cache edits.

The separate native patch, build-tools/partition-alloc-lazy-frameworks.patch,
targets PartitionAlloc commit 46efd4d0ef7727ead34d1ee15fb4e10eb1574a98.
Forward application and reverse checks passed against a fresh upstream
checkout. The repository patch also applied against a clean base checkout.

Startup uses one V8 worker and loads optional CoreFoundation/Security APIs on
first use. Ordinary mappings avoid the entitlement query; JIT mappings retain
the system policy check. NSDate bridges retain native Objective-C behavior in
a separate archive member.

startup-final-150x2.json contains all samples. Each batch has 150 runs per
binary, randomly interleaved after five warmups each, with a five-second pause
between batches. These measure warm full-process lifetime with tracing off
and stdin at EOF.

| Batch | Baseline median | Candidate median | Saving |
| --- | ---: | ---: | ---: |
| 1 | 8.146 ms | 6.323 ms | 1.823 ms |
| 2 | 8.175 ms | 6.317 ms | 1.858 ms |

The improvement falls short of the requested 2 ms minimum. Preserved fixtures
src/shell-startup-baseline.zig and src/shell-startup-candidate.zig share the same
workload, including the current shell's commented-out interactive loop and demo.
Both use the rebuilt native archive. Build the baseline with the original
CoreFoundation/Security framework flags and the candidate without those flags,
then compare with:

    uv run build-tools/compare-startup.py /path/to/baseline /path/to/candidate

Passed: library tests, fresh-process lazy ICU, concurrent framework first use,
CF timezone/string APIs, clock conversion and JIT policy under ad-hoc signing
and hardened-runtime signing without the allow-JIT entitlement.

    zig build test test-icu-lazy -Doptimize=safe -Dprebuilt_v8_path=zig-out/libv8_zig.a
    zig build test-darwin-frameworks -Doptimize=safe -Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
