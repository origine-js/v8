#include <CoreFoundation/CoreFoundation.h>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <thread>
#include <vector>
#include "partition_alloc/partition_alloc_base/time/time.h"

namespace partition_alloc::internal {
// Returns copied JIT policy; owns/releases temporary CF references and retains
// framework code until process exit. Borrows no caller resources.
bool UseMapJit();
}

using SecTaskRef = struct __SecTask*;
// Borrows allocator state until the returned task is released with CFRelease;
// returns an owned task or null and retains no other caller resources.
extern "C" SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef alloc);
// Borrows task through return; returns copied code-signing flags.
extern "C" uint32_t SecTaskGetCodeSignStatus(SecTaskRef task);

// Accepts a copied assertion value; aborts on failure and retains no resources.
static void check(bool condition) {
  if (!condition) std::abort();
}

// Borrows argv until return. Owns temporary CF references and threads, releasing
// and joining them before return. API adapters retain modules until process exit.
// Assertions abort, letting the OS reclaim process-owned resources.
int main(int argc, char** argv) {
  // The adapter's first CF load and symbol initialization must be thread-safe.
  std::vector<std::thread> threads;
  for (int index = 0; index < 8; ++index) {
    // Captures no state; owns/releases its CF string within the callback.
    // The creating thread joins every callback before destroying the vector.
    threads.emplace_back([] {
      CFStringRef string = CFStringCreateWithCString(nullptr, "startup", kCFStringEncodingUTF8);
      check(string != nullptr);
      check(CFStringGetLength(string) == 7);
      check(CFGetTypeID(string) == CFStringGetTypeID());
      CFRelease(string);
      check(CFAbsoluteTimeGetCurrent() > 0);
    });
  }
  for (auto& thread : threads) thread.join();
  check(CFArrayGetTypeID() && CFBagGetTypeID() && CFBooleanGetTypeID());
  check(CFDataGetTypeID() && CFDateGetTypeID() && CFDictionaryGetTypeID());
  check(CFNullGetTypeID() && CFNumberGetTypeID() && CFSetGetTypeID());
  check(CFURLGetTypeID() && CFUUIDGetTypeID());
  CFTimeZoneRef timezone = CFTimeZoneCopyDefault();
  check(timezone != nullptr);
  CFStringRef name = CFTimeZoneGetName(timezone);
  check(name != nullptr);
  char buffer[256];
  check(CFStringGetMaximumSizeForEncoding(CFStringGetLength(name), kCFStringEncodingUTF8) < 256);
  check(CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8));
  CFRelease(timezone);
  using partition_alloc::internal::base::Time;
  check(std::abs(Time::FromCFAbsoluteTime(12345.125).ToCFAbsoluteTime() - 12345.125) < 0.000001);
  SecTaskRef task = SecTaskCreateFromSelf(nullptr);
  check(task != nullptr);
  const uint32_t flags = SecTaskGetCodeSignStatus(task);
  CFRelease(task);
  const bool allowed = partition_alloc::internal::UseMapJit();
  if (argc > 1) check(allowed == (std::strcmp(argv[1], "allow") == 0));
  else check(!(flags & 0x10000) && allowed);  // CS_RUNTIME absent in the ad-hoc test.
  std::puts("Deferred CF/Security APIs, concurrent first use, clock conversion and JIT policy passed");
}
