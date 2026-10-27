#include "icu.h"

#include <cstddef>
#include <atomic>
#include <new>
#include <zstd.h>
#include "unicode/udata.h"

extern "C" {
extern const unsigned char v8_zig_icu_compressed[];
extern const size_t v8_zig_icu_compressed_size;
extern const size_t v8_zig_icu_original_size;
// Retains provider code for process lifetime; invokes it on first common-data
// lookup outside ICU's data-cache lock. Provider must support concurrent calls.
void v8_zig_icu_set_data_provider(UErrorCode (*provider)());
}

namespace {
std::atomic<bool> data_loaded{false};

// Borrows immutable embedded bytes for this call. On success publishes aligned
// host-owned storage that ICU borrows until process exit; it is never freed early.
// On decoding/registration failure releases storage and returns an ICU error.
// Called once through thread-safe static initialization at first ICU data use,
// outside ICU's data-cache lock. Retains no caller resources.
UErrorCode initialize_data() {
  void* data = ::operator new(v8_zig_icu_original_size, std::align_val_t{16},
                              std::nothrow);
  if (!data) return U_MEMORY_ALLOCATION_ERROR;
  const size_t size = ZSTD_decompress(data, v8_zig_icu_original_size,
                                      v8_zig_icu_compressed,
                                      v8_zig_icu_compressed_size);
  if (ZSTD_isError(size) || size != v8_zig_icu_original_size) {
    ::operator delete(data, std::align_val_t{16});
    return U_INVALID_FORMAT_ERROR;
  }
  UErrorCode status = U_ZERO_ERROR;
  udata_setCommonData(data, &status);
  if (U_FAILURE(status)) {
    ::operator delete(data, std::align_val_t{16});
    return status;
  }
  data_loaded.store(true, std::memory_order_release);
  return status;
}

// Borrows no inputs. Serializes concurrent first requests using static
// initialization; caches success/error and retains published data until exit.
UErrorCode ensure_data() {
  static const UErrorCode status = initialize_data();
  return status;
}

// Borrows no inputs. Configures file policy and retains only a static callback
// until process exit; neither allocates nor decompresses the ICU package.
// Failure publishes no callback and returns false.
bool configure_data() {
  UErrorCode status = U_ZERO_ERROR;
  // Avoid external files silently replacing embedded resources.
  udata_setFileAccess(UDATA_NO_FILES, &status);
  if (U_FAILURE(status)) return false;
  v8_zig_icu_set_data_provider(ensure_data);
  return true;
}
}  // namespace

// Retains only the provider callback until process exit; borrows no caller
// resources. Static initialization serializes configuration and caches failure.
bool v8_zig_icu_initialize() {
  static const bool initialized = configure_data();
  return initialized;
}

// Returns a copied publication flag; thread-safe and retains no resources.
extern "C" bool v8_zig_icu_is_loaded() {
  return data_loaded.load(std::memory_order_acquire);
}
