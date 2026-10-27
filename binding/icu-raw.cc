#include "icu.h"

#include <atomic>
#include "unicode/udata.h"

extern "C" {
// The uncompressed ICU data package (icu-raw-data.S), 16-byte aligned,
// immutable, in the executable's read-only data for the life of the process.
extern const unsigned char v8_zig_icu_raw[];
}

namespace {
std::atomic<bool> data_loaded{false};

// Borrows nothing. Forbids external data files, then publishes the embedded
// package as ICU's common data. Failure publishes nothing and returns false.
// ICU only borrows the bytes: no copy, no heap, pages are mapped on first touch.
bool configure_data() {
  UErrorCode status = U_ZERO_ERROR;
  udata_setFileAccess(UDATA_NO_FILES, &status);
  if (U_FAILURE(status)) return false;
  udata_setCommonData(v8_zig_icu_raw, &status);
  if (U_FAILURE(status)) return false;
  data_loaded.store(true, std::memory_order_release);
  return true;
}
}  // namespace

// Retains nothing; static initialization serializes configuration and caches failure.
bool v8_zig_icu_initialize() {
  static const bool initialized = configure_data();
  return initialized;
}

// Returns a copied publication flag; thread-safe and retains no resources.
extern "C" bool v8_zig_icu_is_loaded() {
  return data_loaded.load(std::memory_order_acquire);
}
