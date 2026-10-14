#pragma once

// Registers the process-lifetime lazy provider before any ICU/V8 use; expands
// no data. Borrows no caller resources. Thread-safe/idempotent; false caches a
// configuration error. First data lookup expands immutable, aligned storage
// retained until process exit. Do not call ICU cleanup/reinitialize afterward.
bool v8_zig_initialize_compressed_icu();

// Returns the process-wide publication state by value; retains no resources.
extern "C" bool v8_zig_is_compressed_icu_loaded();
