#pragma once

// The ICU data provider contract. libv8_zig.a does not contain ICU data or a
// provider: exactly one provider object (`-Dv8_icu=compressed|raw`, built by
// build/icu.build.zig as the `v8_icu` library) is linked into the final program.

// Registers the process-lifetime data provider before any ICU/V8 use. The
// compressed provider expands no data here; the raw one publishes the embedded
// package. Borrows no caller resources. Thread-safe/idempotent; false caches a
// configuration error. Do not call ICU cleanup/reinitialize afterward.
bool v8_zig_icu_initialize();

// Returns the process-wide publication state by value; retains no resources.
// Compressed: true once the first data lookup expanded the package. Raw: true
// once `v8_zig_icu_initialize` published it.
extern "C" bool v8_zig_icu_is_loaded();
