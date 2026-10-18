// https://github.com/denoland/rusty_v8/blob/main/src/support.h

#ifndef SUPPORT_H_
#define SUPPORT_H_

#include <algorithm>
#include <array>
#include <cassert>
#include <memory>
#include <new>
#include <type_traits>
#include <utility>
#include <vector>

#include "cppgc/name-provider.h"
#include "v8-cppgc.h"
#include "v8.h"

// Check assumptions made in binding code.
static_assert(sizeof(bool) == sizeof(uint8_t), "");
static_assert(sizeof(std::unique_ptr<void>) == sizeof(void*), "");

namespace support {

template <std::size_t Len, std::size_t Align>
struct aligned_storage {
    struct type {
    alignas(Align) unsigned char data[Len];
    };
};

template <class T>
using uninit_t = typename aligned_storage<sizeof(T), alignof(T)>::type;

template <class T, class... Args>
class construct_in_place_helper {
 public:
  construct_in_place_helper(uninit_t<T>* buf, Args... args)
      : inner_(std::forward<Args>(args)...) {}

 private:
  T inner_;
};

template <class T, class... Args>
void construct_in_place(uninit_t<T>* buf, Args... args) {
  new (buf)
      construct_in_place_helper<T, Args...>(buf, std::forward<Args>(args)...);
}

// Zig's FFI only supports returning normal C data structures (AKA plain old
// data). There are some situations in the V8 API where functions return non-POD
// data. We use make_pod to carefully adjust the return values so they can be
// passed into Zig.
//
// The destructor of V is never called.
// P is not allowed to have a destructor.
template <class P>
struct make_pod {
  template <class V>
  inline make_pod(V&& value) : pod_(helper<V>(std::move(value))) {}
  template <class V>
  inline make_pod(const V& value) : pod_(helper<V>(value)) {}
  inline operator P() { return pod_; }

 private:
  P pod_;

  // This helper exists to avoid calling the destructor.
  // Using a union is a C++ trick to achieve this.
  template <class V>
  union helper {
    static_assert(std::is_trivial<P>::value &&
                      std::is_standard_layout<P>::value,
                  "type P must a pod type");
    static_assert(sizeof(V) == sizeof(P), "type P must be same size as type V");
    static_assert(alignof(V) == alignof(P),
                  "alignment of type P must be compatible with that of type V");

    inline helper(V&& value) : value_(std::move(value)) {}
    inline helper(const V& value) : value_(value) {}
    inline ~helper() {}

    inline operator P() {
      // Do a memcpy here avoid undefined behavior.
      P result;
      memcpy(&result, this, sizeof result);
      return result;
    }

   private:
    V value_;
  };
};

// The C-ABI compatible equivalent of V8's Maybe<bool>.
enum class MaybeBool { JustFalse = 0, JustTrue = 1, Nothing = 2 };

inline static MaybeBool maybe_to_maybe_bool(v8::Maybe<bool> maybe) {
  if (maybe.IsNothing()) {
    return MaybeBool::Nothing;
  } else if (maybe.FromJust()) {
    return MaybeBool::JustTrue;
  } else {
    return MaybeBool::JustFalse;
  }
}

inline static v8::Maybe<bool> maybe_bool_to_maybe(MaybeBool maybe) {
  switch (maybe) {
    case MaybeBool::JustTrue:
    case MaybeBool::JustFalse:
      return v8::Just<bool>(maybe == MaybeBool::JustTrue);
    default:
      return v8::Nothing<bool>();
  }
}

// Handles cross the C ABI as plain pointers, and "no handle" is always nullptr.
// That is not what an empty Local looks like with V8_ENABLE_DIRECT_HANDLE
// (there it is the tagged value 1, kTaggedNullAddress), so the helpers below
// translate empty <-> nullptr in both directions. With indirect handles an
// empty Local already is nullptr and these checks change nothing.
template <class T>
inline static T* local_to_ptr(v8::Local<T> local) {
  if (local.IsEmpty()) return nullptr;
  auto ptr = *local;
#ifdef V8_ENABLE_DIRECT_HANDLE
  // Smi zero has a null address. Tag 3 cannot represent a strong Local value:
  // Smis are even and aligned heap objects use the strong pointer tag 1.
  if (ptr == nullptr) return reinterpret_cast<T*>(uintptr_t{3});
#endif
  return ptr;
}

template <class T>
inline static const v8::Local<T> ptr_to_local(const T* ptr) {
  static_assert(sizeof(v8::Local<T>) == sizeof(T*), "");
  if (ptr == nullptr) return v8::Local<T>();
#ifdef V8_ENABLE_DIRECT_HANDLE
  if (reinterpret_cast<uintptr_t>(ptr) == 3) ptr = nullptr;
#endif
  auto local = *reinterpret_cast<const v8::Local<T>*>(&ptr);
  assert(*local == ptr);
  return local;
}

// Reference arguments are required locals. With direct handles, a raw zero from
// a V8 callback is a valid Smi, while nullable pointer arguments use null as empty.
template <class T>
inline static v8::Local<T> ref_to_local(const T& ref) {
#ifdef V8_ENABLE_DIRECT_HANDLE
  const T* ptr = &ref;
  if (reinterpret_cast<uintptr_t>(ptr) == 3) ptr = nullptr;
  return *reinterpret_cast<const v8::Local<T>*>(&ptr);
#else
  return ptr_to_local(&ref);
#endif
}

// Direct locals need to decode the normalized zero sentinel in value arrays.
// Indirect handles keep the existing allocation-free view.
template <class T>
class local_array_view {
 public:
  local_array_view(const T* const ptrs[], size_t length) {
#ifdef V8_ENABLE_DIRECT_HANDLE
    // Most arrays need no copy. Only the encoded Smi zero differs from raw V8.
    bool needs_decode = false;
    for (size_t i = 0; i < length; ++i) {
      if (reinterpret_cast<uintptr_t>(ptrs[i]) == 3) needs_decode = true;
    }
    if (needs_decode) {
      storage_.reserve(length);
      for (size_t i = 0; i < length; ++i) storage_.push_back(ptr_to_local(ptrs[i]));
    }
    data_ = storage_.empty()
        ? reinterpret_cast<v8::Local<T>*>(const_cast<T**>(ptrs))
        : storage_.data();
#else
    data_ = reinterpret_cast<v8::Local<T>*>(const_cast<T**>(ptrs));
#endif
  }
  operator v8::Local<T>*() {
    return data_;
  }
 private:
#ifdef V8_ENABLE_DIRECT_HANDLE
  std::vector<v8::Local<T>> storage_;
#endif
  v8::Local<T>* data_;
};

template <class T>
inline static local_array_view<T> const_ptr_array_to_local_array(
    const T* const ptr_array[], size_t length) {
  return local_array_view<T>(ptr_array, length);
}

template <class T>
inline static T* maybe_local_to_ptr(v8::MaybeLocal<T> local) {
  return local_to_ptr(local.FromMaybe(v8::Local<T>()));
}

template <class T>
inline static const v8::MaybeLocal<T> ptr_to_maybe_local(const T* ptr) {
  static_assert(sizeof(v8::MaybeLocal<T>) == sizeof(T*), "");
  return v8::MaybeLocal<T>(ptr_to_local(ptr));
}

template <class T>
inline static v8::Global<T> ptr_to_global(const T* ptr) {
  v8::Global<T> global;
  std::swap(ptr, *reinterpret_cast<const T**>(&global));
  return global;
}

// Because, for some reason, Clang complains that `std::array<void*, 2>` is an
// incomplete type, incompatible with C linkage.
struct two_pointers_t {
  void* a;
  void* b;
};

struct three_pointers_t {
  void* a;
  void* b;
  void* c;
};

}  // namespace support

struct memory_span_t {
  uint8_t* data;
  size_t size;
};

struct const_memory_span_t {
  const uint8_t* data;
  size_t size;
};

// Plain-C view of a v8::FunctionCallbackInfo, read by the Rust bindings
// without calling back into C++ (see v8__FunctionCallbackInfo__GetParts).
struct function_callback_info_parts_t {
  void* isolate;
  void* return_value;
  const void* data;
  int length;
};

#define EACH_TYPED_ARRAY(V) \
  V(Uint8Array)             \
  V(Uint8ClampedArray)      \
  V(Int8Array)              \
  V(Uint16Array)            \
  V(Int16Array)             \
  V(Uint32Array)            \
  V(Int32Array)             \
  V(Float16Array)           \
  V(Float32Array)           \
  V(Float64Array)           \
  V(BigUint64Array)         \
  V(BigInt64Array)

// The cppgc object type backing every Rust-defined garbage-collected object.
// Trace, the destructor and the name are implemented by the embedder (Rust)
// through callbacks stored in the object; see binding.cc.
class RustObj : public v8::Object::Wrappable {
 public:
  ~RustObj();
  void Trace(cppgc::Visitor* visitor) const;
  const char* GetHumanReadableName() const final;
};

// Type-erased std::shared_ptr<v8::WasmStreaming> handed across the C ABI.
struct WasmStreamingSharedPtr {
  std::shared_ptr<v8::WasmStreaming> inner;
};

static_assert(sizeof(WasmStreamingSharedPtr) <= 2 * sizeof(void*),
              "std::shared_ptr<v8::WasmStreaming> size mismatch");

#endif  // SUPPORT_H_
