#include <v8-fast-api-calls.h>
#include <v8-message.h>
#include <v8-typed-array.h>
#include <v8-version-string.h>

#include "support.h"

static size_t v8__ScriptOrigin_SIZE = sizeof(v8::ScriptOrigin);

static size_t v8__Eternal_SIZE = sizeof(v8::Eternal<v8::Data>);

static size_t v8__String__ValueView_SIZE = sizeof(v8::String::ValueView);

static int v8__String__kMaxLength = v8::String::kMaxLength;

static size_t v8__TypedArray__kMaxByteLength = v8::TypedArray::kMaxByteLength;

static size_t v8__TYPED_ARRAY_MAX_SIZE_IN_HEAP =
    V8_TYPED_ARRAY_MAX_SIZE_IN_HEAP;

#define TYPED_ARRAY_MAX_LENGTH(name) \
  static size_t v8__##name##__kMaxLength = v8::name::kMaxLength;
EACH_TYPED_ARRAY(TYPED_ARRAY_MAX_LENGTH)
#undef TYPED_ARRAY_MAX_LENGTH

using v8__CFunction = v8::CFunction;
using v8__CFunctionInfo = v8::CFunctionInfo;
using v8__FastOneByteString = v8::FastOneByteString;
using v8__Isolate__UseCounterFeature = v8::Isolate::UseCounterFeature;
using v8__String__WriteFlags = v8::String::WriteFlags;
using v8__ModuleImportPhase = v8::ModuleImportPhase;
using v8__HeapStatistics = v8::HeapStatistics;
using v8__HeapSpaceStatistics = v8::HeapSpaceStatistics;
using v8__GCType = v8::GCType;
using v8__GCCallbackFlags = v8::GCCallbackFlags;

static uint32_t v8__MAJOR_VERSION = V8_MAJOR_VERSION;
static uint32_t v8__MINOR_VERSION = V8_MINOR_VERSION;
static uint32_t v8__BUILD_NUMBER = V8_BUILD_NUMBER;
static uint32_t v8__PATCH_LEVEL = V8_PATCH_LEVEL;
static const char* v8__VERSION_STRING = V8_VERSION_STRING;
