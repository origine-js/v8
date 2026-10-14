// Keep optional Apple frameworks out of the shell's initial dyld dependency
// graph. Every adapter delegates to the actual system API on first use.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <cstdint>
#include <cstdlib>

namespace {
// Borrows path through dlopen; returns a retained process-lifetime module handle.
// The caller caches it with thread-safe static initialization. Failure aborts.
void* open_framework(const char* path) {
  void* handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
  if (!handle) std::abort();
  return handle;
}

// Returns a borrowed handle valid until exit; thread-safe and allocates no
// caller-owned storage. First load failure aborts; the module is never unloaded.
void* core_foundation() {
  static void* handle = open_framework(
      "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");
  return handle;
}

// Returns a borrowed handle valid until exit, with the same contract as above.
void* security() {
  static void* handle = open_framework(
      "/System/Library/Frameworks/Security.framework/Security");
  return handle;
}

// Borrows module/name through lookup; returns a copied function pointer valid
// until process exit because modules stay loaded. Missing symbols abort.
template <class Function> Function symbol(void* module, const char* name) {
  void* address = dlsym(module, name);
  if (!address) std::abort();
  return reinterpret_cast<Function>(address);
}
}  // namespace

// Each generated adapter accepts/returns values and retains no caller resources;
// its cached system function and module remain valid until process exit.
#define V8_ZIG_CF_TYPE_ID(Type)                                      \
  extern "C" CFTypeID Type##GetTypeID() {                            \
    static auto function = symbol<decltype(&Type##GetTypeID)>(        \
        core_foundation(), #Type "GetTypeID");                       \
    return function();                                              \
  }
V8_ZIG_CF_TYPE_ID(CFArray)
V8_ZIG_CF_TYPE_ID(CFBag)
V8_ZIG_CF_TYPE_ID(CFBoolean)
V8_ZIG_CF_TYPE_ID(CFData)
V8_ZIG_CF_TYPE_ID(CFDate)
V8_ZIG_CF_TYPE_ID(CFDictionary)
V8_ZIG_CF_TYPE_ID(CFNull)
V8_ZIG_CF_TYPE_ID(CFNumber)
V8_ZIG_CF_TYPE_ID(CFSet)
V8_ZIG_CF_TYPE_ID(CFString)
V8_ZIG_CF_TYPE_ID(CFURL)
V8_ZIG_CF_TYPE_ID(CFUUID)
#undef V8_ZIG_CF_TYPE_ID

// Borrows value through return; returns a copied type ID and retains no inputs.
extern "C" CFTypeID CFGetTypeID(CFTypeRef value) {
  static auto function = symbol<decltype(&CFGetTypeID)>(core_foundation(), "CFGetTypeID");
  return function(value);
}

// Consumes one owned CF reference; aliases require a separately retained
// reference to remain valid. Retains no caller resources after return.
extern "C" void CFRelease(CFTypeRef value) {
  static auto function = symbol<decltype(&CFRelease)>(core_foundation(), "CFRelease");
  function(value);
}

// Borrows value through return; returns a copied Boolean and retains no inputs.
extern "C" Boolean CFBooleanGetValue(CFBooleanRef value) {
  static auto function = symbol<decltype(&CFBooleanGetValue)>(core_foundation(), "CFBooleanGetValue");
  return function(value);
}

// Accepts/returns clock values; retains no caller resources.
extern "C" CFAbsoluteTime CFAbsoluteTimeGetCurrent() {
  static auto function = symbol<decltype(&CFAbsoluteTimeGetCurrent)>(core_foundation(), "CFAbsoluteTimeGetCurrent");
  return function();
}

// Borrows null-terminated text through this call. Returns an owned CF string
// released with CFRelease, or null on failure. A custom allocator and its callback
// state must remain valid until that string is released, per the system API.
extern "C" CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char* text, CFStringEncoding encoding) {
  static auto function = symbol<decltype(&CFStringCreateWithCString)>(core_foundation(), "CFStringCreateWithCString");
  return function(alloc, text, encoding);
}

// Borrows immutable string and writable buffer of capacity bytes through return;
// writes into caller-owned storage, retains nothing, and preserves API failure semantics.
extern "C" Boolean CFStringGetCString(CFStringRef string, char* buffer, CFIndex capacity, CFStringEncoding encoding) {
  static auto function = symbol<decltype(&CFStringGetCString)>(core_foundation(), "CFStringGetCString");
  return function(string, buffer, capacity, encoding);
}

// Borrows immutable string through return; returns its copied length.
extern "C" CFIndex CFStringGetLength(CFStringRef string) {
  static auto function = symbol<decltype(&CFStringGetLength)>(core_foundation(), "CFStringGetLength");
  return function(string);
}

// Accepts/returns values; retains no caller resources.
extern "C" CFIndex CFStringGetMaximumSizeForEncoding(CFIndex length, CFStringEncoding encoding) {
  static auto function = symbol<decltype(&CFStringGetMaximumSizeForEncoding)>(core_foundation(), "CFStringGetMaximumSizeForEncoding");
  return function(length, encoding);
}

// Returns an owned CF timezone released with CFRelease, or null on failure;
// retains no caller resources.
extern "C" CFTimeZoneRef CFTimeZoneCopyDefault() {
  static auto function = symbol<decltype(&CFTimeZoneCopyDefault)>(core_foundation(), "CFTimeZoneCopyDefault");
  return function();
}

// Borrows timezone through return; returns a borrowed name valid while timezone
// remains alive. Caller must retain the string to extend its lifetime.
extern "C" CFStringRef CFTimeZoneGetName(CFTimeZoneRef timezone) {
  static auto function = symbol<decltype(&CFTimeZoneGetName)>(core_foundation(), "CFTimeZoneGetName");
  return function(timezone);
}

using SecTaskRef = struct __SecTask*;

// Returns an owned SecTask released with CFRelease, or null on failure. A custom
// allocator and its callback state must stay valid until the task is released.
extern "C" SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef alloc) {
  static auto function = symbol<SecTaskRef (*)(CFAllocatorRef)>(security(), "SecTaskCreateFromSelf");
  return function(alloc);
}

// Borrows task through return; returns copied signing flags and retains no inputs.
extern "C" uint32_t SecTaskGetCodeSignStatus(SecTaskRef task) {
  static auto function = symbol<uint32_t (*)(SecTaskRef)>(security(), "SecTaskGetCodeSignStatus");
  return function(task);
}

// Borrows task/name and optional error slot through return. Returned value and
// reported error are caller-owned CF references released with CFRelease, including
// the error path. Retains no caller input storage.
extern "C" CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef name, CFErrorRef* error) {
  static auto function = symbol<CFTypeRef (*)(SecTaskRef, CFStringRef, CFErrorRef*)>(security(), "SecTaskCopyValueForEntitlement");
  return function(task, name, error);
}

