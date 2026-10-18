// Shims for rusty_v8 (the Rust `v8` crate), ported from denoland/rusty_v8 src/binding.cc.
//
// This is a separate object file on purpose: libv8_zig.a is an archive, so the Zig modules
// never pull this member in, while the Rust crate references it. Several classes here call
// functions that only Rust defines (`*__BASE__*`, `rusty_v8_RustObj_*`, serializer and
// platform delegates); keeping them out of binding.cc means a Zig-only link never needs
// those symbols. Do not call anything defined here from Zig, and keep Zig-facing shims in
// binding.cc.

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <thread>

#include "cppgc/allocation.h"
#include "cppgc/persistent.h"
#include "cppgc/platform.h"
#include "libplatform/libplatform.h"
#include "support.h"
#include "third_party/simdutf/simdutf.h"
#include "unicode/locid.h"
#include "unicode/timezone.h"
#include "unicode/unistr.h"
#include "v8-callbacks.h"
#include "v8-cppgc.h"
#include "v8-fast-api-calls.h"
#include "v8-inspector-protocol.h"
#include "v8-inspector.h"
#include "v8-internal.h"
#include "v8-platform.h"
#include "v8-profiler.h"
#include "v8.h"
#include "../../src/flags/flags.h"
#include "../../third_party/inspector_protocol/crdtp/cbor.h"
#include "../../third_party/inspector_protocol/crdtp/dispatch.h"
#include "../../third_party/inspector_protocol/crdtp/frontend_channel.h"
#include "../../third_party/inspector_protocol/crdtp/json.h"
#include "../../third_party/inspector_protocol/crdtp/parser_handler.h"
#include "../../src/libplatform/default-platform.h"

using namespace support;

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// ---------------------------------------------------------------------------
// rusty_v8 shims (rusty_v8). Ported from denoland/rusty_v8 src/binding.cc so the
// Rust `v8` crate links the same libv8_zig.a as the Zig modules.
//
// Ownership: unless a shim says otherwise it only borrows its arguments for the
// duration of the call, takes no ownership of handles or callbacks, and requires
// the calling thread to be inside the isolate (entered, with a live handle scope)
// exactly like the Zig-facing shims above. Rust-defined callbacks (`*__BASE__*`,
// `rusty_v8_RustObj_*`) are implemented by rusty_v8 and linked into the final binary.
// ---------------------------------------------------------------------------
extern "C" {

// Tagged variants of the aligned-pointer accessors: the Zig-facing versions above
// always use v8::kEmbedderDataTypeTagDefault, rusty_v8 passes its own tag.
void* v8__Object__GetAlignedPointerFromInternalFieldWithTag(
    const v8::Object& self, int index, v8::EmbedderDataTypeTag tag) {
  return ref_to_local(self)->GetAlignedPointerFromInternalField(index, tag);
}

void v8__Object__SetAlignedPointerInInternalFieldWithTag(
    const v8::Object& self, int index, void* value,
    v8::EmbedderDataTypeTag tag) {
  ref_to_local(self)->SetAlignedPointerInInternalField(index, value, tag);
}

// Like v8__WasmStreaming__Finish, but hands V8 a module-caching callback. Borrows
// `self`; the callback is a plain function pointer and is not retained after Finish.
void v8__WasmStreaming__FinishWithCaching(
    WasmStreamingSharedPtr* self,
    void (*callback)(v8::WasmStreaming::ModuleCachingInterface&)) {
  self->inner->Finish(callback);
}

bool v8__V8__EnableWebAssemblyTrapHandler(bool use_v8_signal_handler) {
  return v8::V8::EnableWebAssemblyTrapHandler(use_v8_signal_handler);
}

void v8__Locker__CONSTRUCT(uninit_t<v8::Locker>* buf, v8::Isolate* isolate) {
  construct_in_place<v8::Locker>(buf, isolate);
}

void v8__Locker__DESTRUCT(v8::Locker* self) { self->~Locker(); }

void v8__Unlocker__CONSTRUCT(uninit_t<v8::Unlocker>* buf,
                             v8::Isolate* isolate) {
  construct_in_place<v8::Unlocker>(buf, isolate);
}

void v8__Unlocker__DESTRUCT(v8::Unlocker* self) { self->~Unlocker(); }

bool v8__Locker__IsLocked(v8::Isolate* isolate) {
  return v8::Locker::IsLocked(isolate);
}

v8::Isolate* v8__Isolate__TryGetCurrent() {
  return v8::Isolate::TryGetCurrent();
}

void v8__Isolate__SetIdle(v8::Isolate* isolate, bool is_idle) {
  isolate->SetIdle(is_idle);
}

void v8__Isolate__SetModifyCodeGenerationFromStringsCallback(
    v8::Isolate* isolate,
    v8::ModifyCodeGenerationFromStringsCallback2 callback) {
  isolate->SetModifyCodeGenerationFromStringsCallback(callback);
}

bool v8__Isolate__GetHeapCodeAndMetadataStatistics(v8::Isolate* isolate,
                                                   v8::HeapCodeStatistics* s) {
  return isolate->GetHeapCodeAndMetadataStatistics(s);
}

void v8__ObjectTemplate__SetCallAsFunctionHandler(
    const v8::ObjectTemplate& self, v8::FunctionCallback callback,
    const v8::Value* data_or_null) {
  ptr_to_local(&self)->SetCallAsFunctionHandler(callback,
                                                ptr_to_local(data_or_null));
}

MaybeBool v8__Object__SetLazyDataProperty(
    const v8::Object& self, const v8::Context& context, const v8::Name& key,
    v8::AccessorNameGetterCallback getter, const v8::Value* data_or_null,
    v8::PropertyAttribute attr, v8::SideEffectType getter_side_effect_type,
    v8::SideEffectType setter_side_effect_type) {
  return maybe_to_maybe_bool(ptr_to_local(&self)->SetLazyDataProperty(
      ptr_to_local(&context), ptr_to_local(&key), getter,
      ptr_to_local(data_or_null), attr, getter_side_effect_type,
      setter_side_effect_type));
}

const v8::Value* v8__Object__CallAsFunction(const v8::Object& self,
                                            const v8::Context& context,
                                            const v8::Value& recv, int argc,
                                            const v8::Value* const argv[]) {
  return maybe_local_to_ptr(ptr_to_local(&self)->CallAsFunction(
      ptr_to_local(&context), ptr_to_local(&recv), argc,
      const_ptr_array_to_local_array(argv, argc)));
}

const v8::Value* v8__Object__CallAsConstructor(const v8::Object& self,
                                               const v8::Context& context,
                                               int argc,
                                               const v8::Value* const argv[]) {
  return maybe_local_to_ptr(ptr_to_local(&self)->CallAsConstructor(
      ptr_to_local(&context), argc, const_ptr_array_to_local_array(argv, argc)));
}

void v8__FunctionTemplate__SetAccessorProperty(const v8::FunctionTemplate& self,
                                               const v8::Name& key,
                                               v8::FunctionTemplate& getter,
                                               v8::FunctionTemplate& setter,
                                               v8::PropertyAttribute attr) {
  ptr_to_local(&self)->SetAccessorProperty(
      ptr_to_local(&key), ptr_to_local(&getter), ptr_to_local(&setter), attr);
}

function_callback_info_parts_t v8__FunctionCallbackInfo__GetParts(
    const v8::FunctionCallbackInfo<v8::Value>& self) {
  v8::ReturnValue<v8::Value> rv = self.GetReturnValue();
  return {
      self.GetIsolate(),
      *reinterpret_cast<void**>(&rv),
      local_to_ptr(self.Data()),
      self.Length(),
  };
}

const v8::Value* v8__Module__GetModuleNamespace2(const v8::Module& self,
                                                 v8::ModuleImportPhase phase) {
  return local_to_ptr(ptr_to_local(&self)->GetModuleNamespace(phase));
}

const v8::Value* v8__Module__EvaluateForImportDefer(
    const v8::Module& self, const v8::Context& context) {
  return maybe_local_to_ptr(
      ptr_to_local(&self)->EvaluateForImportDefer(ptr_to_local(&context)));
}

void v8__CpuProfiler__CollectSample(v8::Isolate* isolate,
                                    const uint64_t* trace_id) {
  if (trace_id == nullptr) {
    v8::CpuProfiler::CollectSample(isolate);
  } else {
    v8::CpuProfiler::CollectSample(isolate, *trace_id);
  }
}

void v8__CpuProfiler__UseDetailedSourcePositionsForProfiling(
    v8::Isolate* isolate) {
  v8::CpuProfiler::UseDetailedSourcePositionsForProfiling(isolate);
}

size_t v8__ResourceConstraints__code_range_size_in_bytes(
    const v8::ResourceConstraints* constraints) {
  return constraints->code_range_size_in_bytes();
}

size_t v8__ResourceConstraints__initial_old_generation_size_in_bytes(
    const v8::ResourceConstraints* constraints) {
  return constraints->initial_old_generation_size_in_bytes();
}

size_t v8__ResourceConstraints__initial_young_generation_size_in_bytes(
    const v8::ResourceConstraints* constraints) {
  return constraints->initial_young_generation_size_in_bytes();
}

size_t v8__ResourceConstraints__max_old_generation_size_in_bytes(
    const v8::ResourceConstraints* constraints) {
  return constraints->max_old_generation_size_in_bytes();
}

size_t v8__ResourceConstraints__max_young_generation_size_in_bytes(
    const v8::ResourceConstraints* constraints) {
  return constraints->max_young_generation_size_in_bytes();
}

void v8__ResourceConstraints__set_code_range_size_in_bytes(
    v8::ResourceConstraints* constraints, size_t limit) {
  constraints->set_code_range_size_in_bytes(limit);
}

void v8__ResourceConstraints__set_initial_old_generation_size_in_bytes(
    v8::ResourceConstraints* constraints, size_t initial_size) {
  constraints->set_initial_old_generation_size_in_bytes(initial_size);
}

void v8__ResourceConstraints__set_initial_young_generation_size_in_bytes(
    v8::ResourceConstraints* constraints, size_t initial_size) {
  constraints->set_initial_young_generation_size_in_bytes(initial_size);
}

void v8__ResourceConstraints__set_max_old_generation_size_in_bytes(
    v8::ResourceConstraints* constraints, size_t limit) {
  constraints->set_max_old_generation_size_in_bytes(limit);
}

void v8__ResourceConstraints__set_max_young_generation_size_in_bytes(
    v8::ResourceConstraints* constraints, size_t limit) {
  constraints->set_max_young_generation_size_in_bytes(limit);
}

void v8__ResourceConstraints__set_stack_limit(
    v8::ResourceConstraints* constraints, uint32_t* value) {
  constraints->set_stack_limit(value);
}

uint32_t* v8__ResourceConstraints__stack_limit(
    const v8::ResourceConstraints* constraints) {
  return constraints->stack_limit();
}

struct RustAllocatorVtable {
  void* (*allocate)(void* handle, size_t length);
  void* (*allocate_uninitialized)(void* handle, size_t length);
  void (*free)(void* handle, void* data, size_t length);
  void (*drop)(void* handle);
};

class RustAllocator : public v8::ArrayBuffer::Allocator {
 private:
  void* handle;
  const RustAllocatorVtable* vtable;

 public:
  RustAllocator(void* handle, const RustAllocatorVtable* vtable) {
    this->handle = handle;
    this->vtable = vtable;
  }

  RustAllocator(const RustAllocator& that) = delete;
  RustAllocator(RustAllocator&& that) = delete;
  void operator=(const RustAllocator& that) = delete;
  void operator=(RustAllocator&& that) = delete;

  virtual ~RustAllocator() { vtable->drop(handle); }

  void* Allocate(size_t length) final {
    return vtable->allocate(handle, length);
  }

  void* AllocateUninitialized(size_t length) final {
    return vtable->allocate_uninitialized(handle, length);
  }

  void Free(void* data, size_t length) final {
    vtable->free(handle, data, length);
  }
};

v8::ArrayBuffer::Allocator* v8__ArrayBuffer__Allocator__NewRustAllocator(
    void* handle, const RustAllocatorVtable* vtable) {
  return new RustAllocator(handle, vtable);
}

class ExternalTwoByteString : public v8::String::ExternalStringResource {
 public:
  using RustDestroy = void (*)(uint16_t*, size_t);
  ExternalTwoByteString(uint16_t* data, size_t length, RustDestroy rustDestroy,
                        v8::Isolate* isolate)
      : data_(data),
        length_(length),
        rustDestroy_(rustDestroy),
        isolate_(isolate) {
    isolate_->AdjustAmountOfExternalAllocatedMemory(
        static_cast<int64_t>(length_ * 2));
  }
  ~ExternalTwoByteString() override {
    (*rustDestroy_)(data_, length_);
    isolate_->AdjustAmountOfExternalAllocatedMemory(
        -static_cast<int64_t>(length_ * 2));
  }

  const uint16_t* data() const override { return data_; }

  size_t length() const override { return length_; }

 private:
  uint16_t* data_;
  const size_t length_;
  RustDestroy rustDestroy_;
  v8::Isolate* isolate_;
};

const v8::String* v8__String__NewExternalTwoByte(
    v8::Isolate* isolate, uint16_t* data, size_t length,
    ExternalTwoByteString::RustDestroy rustDestroy) {
  return maybe_local_to_ptr(v8::String::NewExternalTwoByte(
      isolate, new ExternalTwoByteString(data, length, rustDestroy, isolate)));
}

// Rust-side callbacks for trait-based CustomPlatform (PlatformImpl trait).
// Each callback corresponds to a C++ virtual method on TaskRunner or Platform.
// `context` is a pointer to the Rust Box<dyn PlatformImpl>.
// Task ownership is transferred to Rust — Rust is responsible for calling
// Run() and deleting the task.
extern "C" {
void v8__Platform__CustomPlatform__BASE__PostTask(void* context, void* isolate,
                                                  v8::Task* task);
void v8__Platform__CustomPlatform__BASE__PostNonNestableTask(void* context,
                                                             void* isolate,
                                                             v8::Task* task);
void v8__Platform__CustomPlatform__BASE__PostDelayedTask(
    void* context, void* isolate, v8::Task* task, double delay_in_seconds);
void v8__Platform__CustomPlatform__BASE__PostNonNestableDelayedTask(
    void* context, void* isolate, v8::Task* task, double delay_in_seconds);
void v8__Platform__CustomPlatform__BASE__PostIdleTask(void* context,
                                                      void* isolate,
                                                      v8::IdleTask* task);
void v8__Platform__CustomPlatform__BASE__DROP(void* context);
}

// FFI functions for running and deleting V8 tasks from Rust.
extern "C" {
void v8__Task__Run(v8::Task* task) { task->Run(); }
void v8__Task__DELETE(v8::Task* task) { delete task; }
void v8__IdleTask__Run(v8::IdleTask* task, double deadline_in_seconds) {
  task->Run(deadline_in_seconds);
}
void v8__IdleTask__DELETE(v8::IdleTask* task) { delete task; }
}

// TaskRunner wrapper that intercepts all PostTask* virtual methods and
// transfers task ownership to Rust via the PlatformImpl trait. The Rust
// side is responsible for scheduling and calling task->Run().
//
// The wrapped runner is kept for capability queries (IdleTasksEnabled, etc.)
// but tasks are NOT forwarded to it — Rust owns them entirely.
class CustomTaskRunner final : public v8::TaskRunner {
 public:
  CustomTaskRunner(std::shared_ptr<v8::TaskRunner> wrapped, void* context,
                   v8::Isolate* isolate)
      : wrapped_(std::move(wrapped)), context_(context), isolate_(isolate) {}

  bool IdleTasksEnabled() override { return wrapped_->IdleTasksEnabled(); }
  bool NonNestableTasksEnabled() const override {
    return wrapped_->NonNestableTasksEnabled();
  }
  bool NonNestableDelayedTasksEnabled() const override {
    return wrapped_->NonNestableDelayedTasksEnabled();
  }

 protected:
  void PostTaskImpl(std::unique_ptr<v8::Task> task,
                    const v8::SourceLocation& location) override {
    v8__Platform__CustomPlatform__BASE__PostTask(
        context_, static_cast<void*>(isolate_), task.release());
  }
  void PostNonNestableTaskImpl(std::unique_ptr<v8::Task> task,
                               const v8::SourceLocation& location) override {
    v8__Platform__CustomPlatform__BASE__PostNonNestableTask(
        context_, static_cast<void*>(isolate_), task.release());
  }
  void PostDelayedTaskImpl(std::unique_ptr<v8::Task> task,
                           double delay_in_seconds,
                           const v8::SourceLocation& location) override {
    v8__Platform__CustomPlatform__BASE__PostDelayedTask(
        context_, static_cast<void*>(isolate_), task.release(),
        delay_in_seconds > 0 ? delay_in_seconds : 0.0);
  }
  void PostNonNestableDelayedTaskImpl(
      std::unique_ptr<v8::Task> task, double delay_in_seconds,
      const v8::SourceLocation& location) override {
    v8__Platform__CustomPlatform__BASE__PostNonNestableDelayedTask(
        context_, static_cast<void*>(isolate_), task.release(),
        delay_in_seconds > 0 ? delay_in_seconds : 0.0);
  }
  void PostIdleTaskImpl(std::unique_ptr<v8::IdleTask> task,
                        const v8::SourceLocation& location) override {
    v8__Platform__CustomPlatform__BASE__PostIdleTask(
        context_, static_cast<void*>(isolate_), task.release());
  }

 private:
  std::shared_ptr<v8::TaskRunner> wrapped_;
  void* context_;
  v8::Isolate* isolate_;
};

// Platform subclass that wraps each isolate's TaskRunner to notify Rust
// when foreground tasks are posted. Follows the inspector API pattern.
//
// NotifyIsolateShutdown is NOT intercepted here because it is not virtual
// on DefaultPlatform — V8's free function does static_cast<DefaultPlatform*>
// and calls it directly, bypassing any override. Isolate cleanup must be
// handled on the Rust side (e.g. in the isolate's Drop impl).
class CustomPlatform : public v8::platform::DefaultPlatform {
  using IdleTaskSupport = v8::platform::IdleTaskSupport;

 public:
  CustomPlatform(int thread_pool_size, IdleTaskSupport idle_task_support,
                 bool unprotected, void* context)
      : DefaultPlatform(thread_pool_size, idle_task_support),
        unprotected_(unprotected),
        context_(context) {}

  // SAFETY: The platform is single-owner (via unique_ptr). The destructor
  // runs after all isolates have been disposed and no more task runner
  // callbacks can fire, so DROP does not race with other callbacks.
  ~CustomPlatform() override {
    v8__Platform__CustomPlatform__BASE__DROP(context_);
  }

  std::shared_ptr<v8::TaskRunner> GetForegroundTaskRunner(
      v8::Isolate* isolate, v8::TaskPriority priority) override {
    auto original = DefaultPlatform::GetForegroundTaskRunner(isolate, priority);
    std::lock_guard<std::mutex> lock(mutex_);
    auto key = std::make_pair(isolate, priority);
    auto it = runners_.find(key);
    if (it != runners_.end()) {
      auto runner = it->second.lock();
      if (runner) return runner;
    }
    auto custom =
        std::make_shared<CustomTaskRunner>(original, context_, isolate);
    runners_[key] = custom;
    return custom;
  }

  // When unprotected, disable thread-isolated allocations (same as
  // UnprotectedDefaultPlatform). Required when isolates may be created on
  // threads other than the one that called v8::V8::Initialize (e.g. worker
  // threads in Deno).
  v8::ThreadIsolatedAllocator* GetThreadIsolatedAllocator() override {
    if (unprotected_) return nullptr;
    return DefaultPlatform::GetThreadIsolatedAllocator();
  }

 private:
  bool unprotected_;
  void* context_;
  std::mutex mutex_;
  // weak_ptr so runners are kept alive only while V8 holds a reference.
  // When V8 drops its shared_ptr (e.g. on isolate shutdown), the weak_ptr
  // expires and a fresh wrapper is created if GetForegroundTaskRunner is
  // called again. This avoids preventing cleanup of the underlying runner.
  std::map<std::pair<v8::Isolate*, v8::TaskPriority>,
           std::weak_ptr<CustomTaskRunner>>
      runners_;
};

v8::Platform* v8__Platform__NewCustomPlatform(int thread_pool_size,
                                              bool idle_task_support,
                                              bool unprotected, void* context) {
  if (thread_pool_size < 1) {
    thread_pool_size = std::thread::hardware_concurrency();
  }
  thread_pool_size = std::max(std::min(thread_pool_size, 16), 1);
  return std::make_unique<CustomPlatform>(
             thread_pool_size,
             idle_task_support ? v8::platform::IdleTaskSupport::kEnabled
                               : v8::platform::IdleTaskSupport::kDisabled,
             unprotected, context)
      .release();
}

void v8__WasmStreaming__SetHasCompiledModuleBytes(
    WasmStreamingSharedPtr* self) {
  self->inner->SetHasCompiledModuleBytes();
}

const_memory_span_t v8__ModuleCachingInterface__GetWireBytes(
    const v8::WasmStreaming::ModuleCachingInterface& self) {
  v8::MemorySpan<const uint8_t> span = self.GetWireBytes();
  return {span.data(), span.size()};
}

bool v8__ModuleCachingInterface__SetCachedCompiledModuleBytes(
    v8::WasmStreaming::ModuleCachingInterface& self,
    const_memory_span_t bytes) {
  v8::MemorySpan<const uint8_t> bytes_span{bytes.data, bytes.size};
  return self.SetCachedCompiledModuleBytes(bytes_span);
}

v8::WasmModuleCompilation* v8__WasmModuleCompilation__NEW() {
  return new v8::WasmModuleCompilation();
}

void v8__WasmModuleCompilation__DELETE(v8::WasmModuleCompilation* self) {
  delete self;
}

void v8__WasmModuleCompilation__OnBytesReceived(v8::WasmModuleCompilation* self,
                                                const uint8_t* bytes,
                                                size_t size) {
  self->OnBytesReceived(bytes, size);
}

void v8__WasmModuleCompilation__Finish(
    v8::WasmModuleCompilation* self, v8::Isolate* isolate,
    void (*caching_callback)(v8::WasmStreaming::ModuleCachingInterface&),
    void (*resolution_callback)(void* data, const v8::WasmModuleObject* module,
                                const v8::Value* error),
    void* resolution_data, void (*drop_resolution_data)(void* data)) {
  // Use shared_ptr to reference-count the Rust closure data through
  // std::function's copy semantics. The custom deleter calls back into Rust
  // to drop the boxed closure when the last copy is destroyed.
  auto shared_data = std::shared_ptr<void>(
      resolution_data,
      [drop_resolution_data](void* p) { drop_resolution_data(p); });
  self->Finish(
      isolate, caching_callback,
      [resolution_callback, shared_data](auto result) {
        if (auto* module =
                std::get_if<v8::Local<v8::WasmModuleObject>>(&result)) {
          resolution_callback(shared_data.get(), local_to_ptr(*module),
                              nullptr);
        } else {
          resolution_callback(
              shared_data.get(), nullptr,
              local_to_ptr(std::get<v8::Local<v8::Value>>(result)));
        }
      });
}

void v8__WasmModuleCompilation__Abort(v8::WasmModuleCompilation* self) {
  self->Abort();
}

void v8__WasmModuleCompilation__SetHasCompiledModuleBytes(
    v8::WasmModuleCompilation* self) {
  self->SetHasCompiledModuleBytes();
}

void v8__WasmModuleCompilation__SetMoreFunctionsCanBeSerializedCallback(
    v8::WasmModuleCompilation* self,
    void (*callback)(void* data, v8::CompiledWasmModule* compiled_module),
    void* data, void (*drop_data)(void* data)) {
  auto shared_data =
      std::shared_ptr<void>(data, [drop_data](void* p) { drop_data(p); });
  self->SetMoreFunctionsCanBeSerializedCallback(
      [callback, shared_data](v8::CompiledWasmModule module) {
        auto* heap_module = new v8::CompiledWasmModule(std::move(module));
        callback(shared_data.get(), heap_module);
      });
}

void v8__WasmModuleCompilation__SetUrl(v8::WasmModuleCompilation* self,
                                       const char* url, size_t length) {
  self->SetUrl(url, length);
}

size_t icu_get_default_time_zone(char* output, size_t output_len) {
  icu::UnicodeString id;
  std::unique_ptr<icu::TimeZone> tz(icu::TimeZone::createDefault());
  tz->getID(id);
  icu::CheckedArrayByteSink sink(output, static_cast<uint32_t>(output_len));
  id.toUTF8(sink);
  assert(!sink.Overflowed());
  // Deliberately not `NumberOfBytesAppended()`: that counts bytes the sink was
  // asked to write, so on overflow it exceeds `output_len` and the caller would
  // read past the buffer (the assert above is compiled out in release builds).
  return sink.NumberOfBytesWritten();
}

// NOTE: the parameter is deliberately not named `timezone`; glibc's <time.h>
// declares a global with that name and the build uses -Werror,-Wshadow.
bool icu_set_default_time_zone(const char* time_zone_id) {
  // `createTimeZone()` never fails: an id it does not recognize yields the
  // special "unknown" zone (which behaves as GMT). Detect that and report it
  // instead of silently installing GMT.
  std::unique_ptr<icu::TimeZone> tz(icu::TimeZone::createTimeZone(
      icu::UnicodeString::fromUTF8(time_zone_id)));
  icu::UnicodeString id;
  tz->getID(id);
  if (id == icu::UnicodeString(UCAL_UNKNOWN_ZONE_ID, -1, US_INV)) {
    return false;
  }
  // Takes ownership of the created TimeZone and installs it as the process
  // wide default, so ICU (and therefore V8's Date implementation) resolves
  // the given id regardless of how the host reports its time zone.
  icu::TimeZone::adoptDefault(tz.release());
  return true;
}

void rusty_v8_RustObj_trace(const RustObj*, cppgc::Visitor*);
const char* rusty_v8_RustObj_get_name(const RustObj*);
void rusty_v8_RustObj_drop(RustObj*);

RustObj::~RustObj() { rusty_v8_RustObj_drop(this); }

void RustObj::Trace(cppgc::Visitor* visitor) const {
  rusty_v8_RustObj_trace(this, visitor);
}

const char* RustObj::GetHumanReadableName() const {
  return rusty_v8_RustObj_get_name(this);
}

RustObj* v8__Object__Unwrap(v8::Isolate* isolate, const v8::Object& wrapper,
                            v8::CppHeapPointerTag tag) {
  v8::CppHeapPointerTagRange tag_range(tag, tag);
  return static_cast<RustObj*>(
      v8::Object::Unwrap(isolate, ptr_to_local(&wrapper), tag_range));
}

void v8__Object__Wrap(v8::Isolate* isolate, const v8::Object& wrapper,
                      RustObj* value, v8::CppHeapPointerTag tag) {
  v8::Object::Wrap(isolate, ptr_to_local(&wrapper), value, tag);
}

v8::CppHeap* v8__Isolate__GetCppHeap(v8::Isolate* isolate) {
  return isolate->GetCppHeap();
}

void cppgc__initialize_process(v8::Platform* platform) {
  cppgc::InitializeProcess(platform->GetPageAllocator());
}

void cppgc__shutdown_process() { cppgc::ShutdownProcess(); }

v8::CppHeap* v8__CppHeap__Create(v8::Platform* platform,
                                 cppgc::Heap::MarkingType marking_support,
                                 cppgc::Heap::SweepingType sweeping_support) {
  v8::CppHeapCreateParams params{{}};
  params.marking_support = marking_support;
  params.sweeping_support = sweeping_support;
  std::unique_ptr<v8::CppHeap> heap = v8::CppHeap::Create(platform, params);
  return heap.release();
}

void v8__CppHeap__Terminate(v8::CppHeap* cpp_heap) { cpp_heap->Terminate(); }

void v8__CppHeap__DELETE(v8::CppHeap* self) { delete self; }

void cppgc__heap__enable_detached_garbage_collections_for_testing(
    v8::CppHeap* heap) {
  heap->EnableDetachedGarbageCollectionsForTesting();
}

void cppgc__heap__collect_garbage_for_testing(
    v8::CppHeap* heap, cppgc::EmbedderStackState stack_state) {
  heap->CollectGarbageForTesting(stack_state);
}

class alignas(16) RustObjButAlign16 : public RustObj {};

RustObj* cppgc__make_garbage_collectable(v8::CppHeap* heap, size_t size,
                                         size_t alignment) {
  if (alignment <= 8) {
    return cppgc::MakeGarbageCollected<RustObj>(heap->GetAllocationHandle(),
                                                cppgc::AdditionalBytes(size));
  }
  if (alignment <= 16) {
    return cppgc::MakeGarbageCollected<RustObjButAlign16>(
        heap->GetAllocationHandle(), cppgc::AdditionalBytes(size));
  }
  return nullptr;
}

void cppgc__Visitor__Trace__Member(cppgc::Visitor* visitor,
                                   cppgc::Member<RustObj>* member) {
  visitor->Trace(*member);
}

void cppgc__Visitor__Trace__WeakMember(cppgc::Visitor* visitor,
                                       cppgc::WeakMember<RustObj>* member) {
  visitor->Trace(*member);
}

void cppgc__Visitor__Trace__TracedReference(
    cppgc::Visitor* visitor, v8::TracedReference<v8::Data>* ref) {
  visitor->Trace(*ref);
}

void cppgc__Member__CONSTRUCT(uninit_t<cppgc::Member<RustObj>>* buf,
                              RustObj* other) {
  construct_in_place<cppgc::Member<RustObj>>(buf, other);
}

void cppgc__Member__DESTRUCT(cppgc::Member<RustObj>* self) {
  self->~BasicMember();
}

RustObj* cppgc__Member__Get(cppgc::Member<RustObj>* member) {
  return member->Get();
}

void cppgc__Member__Assign(cppgc::Member<RustObj>* member, RustObj* other) {
  member->operator=(other);
}

void cppgc__WeakMember__CONSTRUCT(uninit_t<cppgc::WeakMember<RustObj>>* buf,
                                  RustObj* other) {
  construct_in_place<cppgc::WeakMember<RustObj>>(buf, other);
}

void cppgc__WeakMember__DESTRUCT(cppgc::WeakMember<RustObj>* self) {
  self->~BasicMember();
}

RustObj* cppgc__WeakMember__Get(cppgc::WeakMember<RustObj>* member) {
  return member->Get();
}

void cppgc__WeakMember__Assign(cppgc::WeakMember<RustObj>* member,
                               RustObj* other) {
  member->operator=(other);
}

cppgc::Persistent<RustObj>* cppgc__Persistent__CONSTRUCT(RustObj* obj) {
  return new cppgc::Persistent<RustObj>(obj);
}

void cppgc__Persistent__DESTRUCT(cppgc::Persistent<RustObj>* self) {
  delete self;
}

void cppgc__Persistent__Assign(cppgc::Persistent<RustObj>* self, RustObj* ptr) {
  self->operator=(ptr);
}

RustObj* cppgc__Persistent__Get(cppgc::Persistent<RustObj>* self) {
  return self->Get();
}

cppgc::WeakPersistent<RustObj>* cppgc__WeakPersistent__CONSTRUCT(RustObj* obj) {
  return new cppgc::WeakPersistent<RustObj>(obj);
}

void cppgc__WeakPersistent__DESTRUCT(cppgc::WeakPersistent<RustObj>* self) {
  delete self;
}

void cppgc__WeakPersistent__Assign(cppgc::WeakPersistent<RustObj>* self,
                                   RustObj* ptr) {
  self->operator=(ptr);
}

RustObj* cppgc__WeakPersistent__Get(cppgc::WeakPersistent<RustObj>* self) {
  return self->Get();
}

}  // extern "C"

// v8::ValueSerializer::Delegate

extern "C" {
void v8__ValueSerializer__Delegate__ThrowDataCloneError(
    v8::ValueSerializer::Delegate* self, v8::Local<v8::String> message);

bool v8__ValueSerializer__Delegate__HasCustomHostObject(
    v8::ValueSerializer::Delegate* self, v8::Isolate* isolate);

MaybeBool v8__ValueSerializer__Delegate__IsHostObject(
    v8::ValueSerializer::Delegate* self, v8::Isolate* isolate,
    v8::Local<v8::Object> object);

MaybeBool v8__ValueSerializer__Delegate__WriteHostObject(
    v8::ValueSerializer::Delegate* self, v8::Isolate* isolate,
    v8::Local<v8::Object> object);

bool v8__ValueSerializer__Delegate__GetSharedArrayBufferId(
    v8::ValueSerializer::Delegate* self, v8::Isolate* isolate,
    v8::Local<v8::SharedArrayBuffer> shared_array_buffer, uint32_t* result);

bool v8__ValueSerializer__Delegate__GetWasmModuleTransferId(
    v8::ValueSerializer::Delegate* self, v8::Isolate* isolate,
    v8::Local<v8::WasmModuleObject> module, uint32_t* result);

void* v8__ValueSerializer__Delegate__ReallocateBufferMemory(
    v8::ValueSerializer::Delegate* self, void* old_buffer, size_t size,
    size_t* actual_size);

void v8__ValueSerializer__Delegate__FreeBufferMemory(
    v8::ValueSerializer::Delegate* self, void* buffer);
}

struct v8__ValueSerializer__Delegate : public v8::ValueSerializer::Delegate {
  void ThrowDataCloneError(v8::Local<v8::String> message) override {
    v8__ValueSerializer__Delegate__ThrowDataCloneError(this, message);
  }

  bool HasCustomHostObject(v8::Isolate* isolate) override {
    return v8__ValueSerializer__Delegate__HasCustomHostObject(this, isolate);
  }

  v8::Maybe<bool> IsHostObject(v8::Isolate* isolate,
                               v8::Local<v8::Object> object) override {
    return maybe_bool_to_maybe(
        v8__ValueSerializer__Delegate__IsHostObject(this, isolate, object));
  }

  v8::Maybe<bool> WriteHostObject(v8::Isolate* isolate,
                                  v8::Local<v8::Object> object) override {
    return maybe_bool_to_maybe(
        v8__ValueSerializer__Delegate__WriteHostObject(this, isolate, object));
  }

  v8::Maybe<uint32_t> GetSharedArrayBufferId(
      v8::Isolate* isolate,
      v8::Local<v8::SharedArrayBuffer> shared_array_buffer) override {
    uint32_t result = 0;
    if (!v8__ValueSerializer__Delegate__GetSharedArrayBufferId(
            this, isolate, shared_array_buffer, &result)) {
      // Forward to the original method. It'll throw DataCloneError.
      return v8::ValueSerializer::Delegate::GetSharedArrayBufferId(
          isolate, shared_array_buffer);
    }
    return v8::Just(result);
  }

  v8::Maybe<uint32_t> GetWasmModuleTransferId(
      v8::Isolate* isolate, v8::Local<v8::WasmModuleObject> module) override {
    uint32_t result = 0;
    if (!v8__ValueSerializer__Delegate__GetWasmModuleTransferId(
            this, isolate, module, &result))
      return v8::Nothing<uint32_t>();
    return v8::Just(result);
  }

  void* ReallocateBufferMemory(void* old_buffer, size_t size,
                               size_t* actual_size) override {
    return v8__ValueSerializer__Delegate__ReallocateBufferMemory(
        this, old_buffer, size, actual_size);
  }

  void FreeBufferMemory(void* buffer) override {
    v8__ValueSerializer__Delegate__FreeBufferMemory(this, buffer);
  }
};

extern "C" {
void v8__ValueSerializer__Delegate__CONSTRUCT(
    uninit_t<v8__ValueSerializer__Delegate>* buf) {
  static_assert(sizeof(v8__ValueSerializer__Delegate) == sizeof(size_t),
                "v8__ValueSerializer__Delegate size mismatch");
  construct_in_place<v8__ValueSerializer__Delegate>(buf);
}
}

// v8::ValueSerializer

extern "C" {
void v8__ValueSerializer__CONSTRUCT(uninit_t<v8::ValueSerializer>* buf,
                                    v8::Isolate* isolate,
                                    v8::ValueSerializer::Delegate* delegate) {
  static_assert(sizeof(v8::ValueSerializer) == sizeof(size_t),
                "v8::ValueSerializer size mismatch");
  construct_in_place<v8::ValueSerializer>(buf, isolate, delegate);
}

void v8__ValueSerializer__DESTRUCT(v8::ValueSerializer* self) {
  self->~ValueSerializer();
}

void v8__ValueSerializer__Release(v8::ValueSerializer* self, uint8_t** ptr,
                                  size_t* size) {
  auto result = self->Release();
  *ptr = result.first;
  *size = result.second;
}

void v8__ValueSerializer__SetTreatArrayBufferViewsAsHostObjects(
    v8::ValueSerializer* self, bool mode) {
  self->SetTreatArrayBufferViewsAsHostObjects(mode);
}

void v8__ValueSerializer__WriteHeader(v8::ValueSerializer* self) {
  self->WriteHeader();
}

MaybeBool v8__ValueSerializer__WriteValue(v8::ValueSerializer* self,
                                          v8::Local<v8::Context> context,
                                          v8::Local<v8::Value> value) {
  return maybe_to_maybe_bool(self->WriteValue(context, value));
}

void v8__ValueSerializer__TransferArrayBuffer(
    v8::ValueSerializer* self, uint32_t transfer_id,
    v8::Local<v8::ArrayBuffer> array_buffer) {
  self->TransferArrayBuffer(transfer_id, array_buffer);
}

void v8__ValueSerializer__WriteUint32(v8::ValueSerializer* self,
                                      uint32_t value) {
  self->WriteUint32(value);
}

void v8__ValueSerializer__WriteUint64(v8::ValueSerializer* self,
                                      uint64_t value) {
  self->WriteUint64(value);
}

void v8__ValueSerializer__WriteDouble(v8::ValueSerializer* self, double value) {
  self->WriteDouble(value);
}

void v8__ValueSerializer__WriteRawBytes(v8::ValueSerializer* self,
                                        const void* source, size_t length) {
  self->WriteRawBytes(source, length);
}
}

// v8::ValueDeserializer::Delegate

extern "C" {
v8::Object* v8__ValueDeserializer__Delegate__ReadHostObject(
    v8::ValueDeserializer::Delegate* self, v8::Isolate* isolate);

v8::SharedArrayBuffer*
v8__ValueDeserializer__Delegate__GetSharedArrayBufferFromId(
    v8::ValueDeserializer::Delegate* self, v8::Isolate* isolate,
    uint32_t transfer_id);

v8::WasmModuleObject* v8__ValueDeserializer__Delegate__GetWasmModuleFromId(
    v8::ValueDeserializer::Delegate* self, v8::Isolate* isolate,
    uint32_t clone_id);
}

struct v8__ValueDeserializer__Delegate
    : public v8::ValueDeserializer::Delegate {
  v8::MaybeLocal<v8::Object> ReadHostObject(v8::Isolate* isolate) override {
    return ptr_to_maybe_local(
        v8__ValueDeserializer__Delegate__ReadHostObject(this, isolate));
  }

  v8::MaybeLocal<v8::SharedArrayBuffer> GetSharedArrayBufferFromId(
      v8::Isolate* isolate, uint32_t transfer_id) override {
    return ptr_to_maybe_local(
        v8__ValueDeserializer__Delegate__GetSharedArrayBufferFromId(
            this, isolate, transfer_id));
  }

  v8::MaybeLocal<v8::WasmModuleObject> GetWasmModuleFromId(
      v8::Isolate* isolate, uint32_t clone_id) override {
    return ptr_to_maybe_local(
        v8__ValueDeserializer__Delegate__GetWasmModuleFromId(this, isolate,
                                                             clone_id));
  }
};

extern "C" {
void v8__ValueDeserializer__Delegate__CONSTRUCT(
    uninit_t<v8__ValueDeserializer__Delegate>* buf) {
  static_assert(sizeof(v8__ValueDeserializer__Delegate) == sizeof(size_t),
                "v8__ValueDeserializer__Delegate size mismatch");
  construct_in_place<v8__ValueDeserializer__Delegate>(buf);
}
}

// v8::ValueDeserializer

extern "C" {
void v8__ValueDeserializer__CONSTRUCT(
    uninit_t<v8::ValueDeserializer>* buf, v8::Isolate* isolate,
    const uint8_t* data, size_t size,
    v8::ValueDeserializer::Delegate* delegate) {
  static_assert(sizeof(v8::ValueDeserializer) == sizeof(size_t),
                "v8::ValueDeserializer size mismatch");
  construct_in_place<v8::ValueDeserializer>(buf, isolate, data, size, delegate);
}

void v8__ValueDeserializer__DESTRUCT(v8::ValueDeserializer* self) {
  self->~ValueDeserializer();
}

MaybeBool v8__ValueDeserializer__ReadHeader(v8::ValueDeserializer* self,
                                            v8::Local<v8::Context> context) {
  return maybe_to_maybe_bool(self->ReadHeader(context));
}

v8::Value* v8__ValueDeserializer__ReadValue(v8::ValueDeserializer* self,
                                            v8::Local<v8::Context> context) {
  return maybe_local_to_ptr(self->ReadValue(context));
}

void v8__ValueDeserializer__TransferArrayBuffer(
    v8::ValueDeserializer* self, uint32_t transfer_id,
    v8::Local<v8::ArrayBuffer> array_buffer) {
  self->TransferArrayBuffer(transfer_id, array_buffer);
}

void v8__ValueDeserializer__TransferSharedArrayBuffer(
    v8::ValueDeserializer* self, uint32_t transfer_id,
    v8::Local<v8::SharedArrayBuffer> shared_array_buffer) {
  self->TransferSharedArrayBuffer(transfer_id, shared_array_buffer);
}

void v8__ValueDeserializer__SetSupportsLegacyWireFormat(
    v8::ValueDeserializer* self, bool supports_legacy_wire_format) {
  self->SetSupportsLegacyWireFormat(supports_legacy_wire_format);
}

bool v8__ValueDeserializer__ReadUint32(v8::ValueDeserializer* self,
                                       uint32_t* value) {
  return self->ReadUint32(value);
}

bool v8__ValueDeserializer__ReadUint64(v8::ValueDeserializer* self,
                                       uint64_t* value) {
  return self->ReadUint64(value);
}

bool v8__ValueDeserializer__ReadDouble(v8::ValueDeserializer* self,
                                       double* value) {
  return self->ReadDouble(value);
}

bool v8__ValueDeserializer__ReadRawBytes(v8::ValueDeserializer* self,
                                         size_t length, const void** data) {
  return self->ReadRawBytes(length, data);
}

uint32_t v8__ValueDeserializer__GetWireFormatVersion(
    v8::ValueDeserializer* self) {
  return self->GetWireFormatVersion();
}
}  // extern "C"

// simdutf

struct simdutf__result {
  int error;
  size_t count;
};

static simdutf__result to_ffi_result(simdutf::result r) {
  return {static_cast<int>(r.error), r.count};
}

extern "C" {

// --- Validation ---

bool simdutf__validate_utf8(const char* buf, size_t len) {
  return simdutf::validate_utf8(buf, len);
}

simdutf__result simdutf__validate_utf8_with_errors(const char* buf,
                                                   size_t len) {
  return to_ffi_result(simdutf::validate_utf8_with_errors(buf, len));
}

bool simdutf__validate_ascii(const char* buf, size_t len) {
  return simdutf::validate_ascii(buf, len);
}

simdutf__result simdutf__validate_ascii_with_errors(const char* buf,
                                                    size_t len) {
  return to_ffi_result(simdutf::validate_ascii_with_errors(buf, len));
}

bool simdutf__validate_utf16le(const char16_t* buf, size_t len) {
  return simdutf::validate_utf16le(buf, len);
}

simdutf__result simdutf__validate_utf16le_with_errors(const char16_t* buf,
                                                      size_t len) {
  return to_ffi_result(simdutf::validate_utf16le_with_errors(buf, len));
}

bool simdutf__validate_utf16be(const char16_t* buf, size_t len) {
  return simdutf::validate_utf16be(buf, len);
}

simdutf__result simdutf__validate_utf16be_with_errors(const char16_t* buf,
                                                      size_t len) {
  return to_ffi_result(simdutf::validate_utf16be_with_errors(buf, len));
}

bool simdutf__validate_utf32(const char32_t* buf, size_t len) {
  return simdutf::validate_utf32(buf, len);
}

simdutf__result simdutf__validate_utf32_with_errors(const char32_t* buf,
                                                    size_t len) {
  return to_ffi_result(simdutf::validate_utf32_with_errors(buf, len));
}

// --- Conversion: UTF-8 <-> UTF-16LE ---

size_t simdutf__convert_utf8_to_utf16le(const char* input, size_t length,
                                        char16_t* output) {
  return simdutf::convert_utf8_to_utf16le(input, length, output);
}

simdutf__result simdutf__convert_utf8_to_utf16le_with_errors(const char* input,
                                                             size_t length,
                                                             char16_t* output) {
  return to_ffi_result(
      simdutf::convert_utf8_to_utf16le_with_errors(input, length, output));
}

size_t simdutf__convert_valid_utf8_to_utf16le(const char* input, size_t length,
                                              char16_t* output) {
  return simdutf::convert_valid_utf8_to_utf16le(input, length, output);
}

size_t simdutf__convert_utf16le_to_utf8(const char16_t* input, size_t length,
                                        char* output) {
  return simdutf::convert_utf16le_to_utf8(input, length, output);
}

simdutf__result simdutf__convert_utf16le_to_utf8_with_errors(
    const char16_t* input, size_t length, char* output) {
  return to_ffi_result(
      simdutf::convert_utf16le_to_utf8_with_errors(input, length, output));
}

size_t simdutf__convert_valid_utf16le_to_utf8(const char16_t* input,
                                              size_t length, char* output) {
  return simdutf::convert_valid_utf16le_to_utf8(input, length, output);
}

// --- Conversion: UTF-8 <-> UTF-16BE ---

size_t simdutf__convert_utf8_to_utf16be(const char* input, size_t length,
                                        char16_t* output) {
  return simdutf::convert_utf8_to_utf16be(input, length, output);
}

size_t simdutf__convert_utf16be_to_utf8(const char16_t* input, size_t length,
                                        char* output) {
  return simdutf::convert_utf16be_to_utf8(input, length, output);
}

// --- Conversion: UTF-8 <-> Latin-1 ---

size_t simdutf__convert_utf8_to_latin1(const char* input, size_t length,
                                       char* output) {
  return simdutf::convert_utf8_to_latin1(input, length, output);
}

simdutf__result simdutf__convert_utf8_to_latin1_with_errors(const char* input,
                                                            size_t length,
                                                            char* output) {
  return to_ffi_result(
      simdutf::convert_utf8_to_latin1_with_errors(input, length, output));
}

size_t simdutf__convert_valid_utf8_to_latin1(const char* input, size_t length,
                                             char* output) {
  return simdutf::convert_valid_utf8_to_latin1(input, length, output);
}

size_t simdutf__convert_latin1_to_utf8(const char* input, size_t length,
                                       char* output) {
  return simdutf::convert_latin1_to_utf8(input, length, output);
}

// --- Conversion: Latin-1 <-> UTF-16LE ---

size_t simdutf__convert_latin1_to_utf16le(const char* input, size_t length,
                                          char16_t* output) {
  return simdutf::convert_latin1_to_utf16le(input, length, output);
}

size_t simdutf__convert_utf16le_to_latin1(const char16_t* input, size_t length,
                                          char* output) {
  return simdutf::convert_utf16le_to_latin1(input, length, output);
}

// --- Conversion: UTF-8 <-> UTF-32 ---

size_t simdutf__convert_utf8_to_utf32(const char* input, size_t length,
                                      char32_t* output) {
  return simdutf::convert_utf8_to_utf32(input, length, output);
}

size_t simdutf__convert_utf32_to_utf8(const char32_t* input, size_t length,
                                      char* output) {
  return simdutf::convert_utf32_to_utf8(input, length, output);
}

// --- Length calculation ---

size_t simdutf__utf8_length_from_utf16le(const char16_t* input, size_t length) {
  return simdutf::utf8_length_from_utf16le(input, length);
}

size_t simdutf__utf8_length_from_utf16be(const char16_t* input, size_t length) {
  return simdutf::utf8_length_from_utf16be(input, length);
}

size_t simdutf__utf16_length_from_utf8(const char* input, size_t length) {
  return simdutf::utf16_length_from_utf8(input, length);
}

size_t simdutf__utf8_length_from_latin1(const char* input, size_t length) {
  return simdutf::utf8_length_from_latin1(input, length);
}

size_t simdutf__latin1_length_from_utf8(const char* input, size_t length) {
  return simdutf::latin1_length_from_utf8(input, length);
}

size_t simdutf__utf32_length_from_utf8(const char* input, size_t length) {
  return simdutf::utf32_length_from_utf8(input, length);
}

size_t simdutf__utf8_length_from_utf32(const char32_t* input, size_t length) {
  return simdutf::utf8_length_from_utf32(input, length);
}

size_t simdutf__utf16_length_from_utf32(const char32_t* input, size_t length) {
  return simdutf::utf16_length_from_utf32(input, length);
}

size_t simdutf__utf32_length_from_utf16le(const char16_t* input,
                                          size_t length) {
  return simdutf::utf32_length_from_utf16le(input, length);
}

// --- Counting ---

size_t simdutf__count_utf8(const char* input, size_t length) {
  return simdutf::count_utf8(input, length);
}

size_t simdutf__count_utf16le(const char16_t* input, size_t length) {
  return simdutf::count_utf16le(input, length);
}

size_t simdutf__count_utf16be(const char16_t* input, size_t length) {
  return simdutf::count_utf16be(input, length);
}

// --- Encoding detection ---

int simdutf__detect_encodings(const char* input, size_t length) {
  return simdutf::detect_encodings(input, length);
}

// --- Base64 ---

size_t simdutf__maximal_binary_length_from_base64(const char* input,
                                                  size_t length) {
  return simdutf::maximal_binary_length_from_base64(input, length);
}

simdutf__result simdutf__base64_to_binary(const char* input, size_t length,
                                          char* output, uint64_t options,
                                          uint64_t last_chunk_options) {
  return to_ffi_result(simdutf::base64_to_binary(
      input, length, output, static_cast<simdutf::base64_options>(options),
      static_cast<simdutf::last_chunk_handling_options>(last_chunk_options)));
}

size_t simdutf__base64_length_from_binary(size_t length, uint64_t options) {
  return simdutf::base64_length_from_binary(
      length, static_cast<simdutf::base64_options>(options));
}

size_t simdutf__binary_to_base64(const char* input, size_t length, char* output,
                                 uint64_t options) {
  return simdutf::binary_to_base64(
      input, length, output, static_cast<simdutf::base64_options>(options));
}

}  // extern "C"

// ---- Rust-implemented inspector/CRDTP callbacks (cargo feature `inspector` of rusty_v8) ----
// The `*__BASE__*` and `crdtp__*` functions declared weak below are defined only by Rust, so
// Zig links, which never reference these classes, resolve them to null.
extern "C" {
// ---- v8_inspector (cargo feature `inspector`) ----

__attribute__((weak)) void v8_inspector__V8Inspector__Channel__BASE__sendResponse(
    v8_inspector::V8Inspector::Channel* self, int callId,
    v8_inspector::StringBuffer* message);
__attribute__((weak)) void v8_inspector__V8Inspector__Channel__BASE__sendNotification(
    v8_inspector::V8Inspector::Channel* self,
    v8_inspector::StringBuffer* message);
__attribute__((weak)) void v8_inspector__V8Inspector__Channel__BASE__flushProtocolNotifications(
    v8_inspector::V8Inspector::Channel* self);

void v8_inspector__V8Inspector__idleStarted(v8_inspector::V8Inspector* self) {
  self->idleStarted();
}

void v8_inspector__V8Inspector__idleFinished(v8_inspector::V8Inspector* self) {
  self->idleFinished();
}

void v8_inspector__V8Inspector__asyncTaskScheduled(
    v8_inspector::V8Inspector* self, v8_inspector::StringView task_name,
    void* task, bool recurring) {
  self->asyncTaskScheduled(task_name, task, recurring);
}

void v8_inspector__V8Inspector__asyncTaskCanceled(
    v8_inspector::V8Inspector* self, void* task) {
  self->asyncTaskCanceled(task);
}

void v8_inspector__V8Inspector__asyncTaskStarted(
    v8_inspector::V8Inspector* self, void* task) {
  self->asyncTaskStarted(task);
}

void v8_inspector__V8Inspector__asyncTaskFinished(
    v8_inspector::V8Inspector* self, void* task) {
  self->asyncTaskFinished(task);
}

void v8_inspector__V8Inspector__allAsyncTasksCanceled(
    v8_inspector::V8Inspector* self) {
  self->allAsyncTasksCanceled();
}

void v8_inspector__V8InspectorSession__releaseObjectGroup(
    v8_inspector::V8InspectorSession* self,
    v8_inspector::StringView object_group) {
  self->releaseObjectGroup(object_group);
}

v8_inspector::protocol::Runtime::API::RemoteObject*
v8_inspector__V8InspectorSession__wrapObject(
    v8_inspector::V8InspectorSession* self, const v8::Context* context,
    const v8::Value* value, v8_inspector::StringView object_group,
    bool generate_preview) {
  return self
      ->wrapObject(ptr_to_local(context), ptr_to_local(value), object_group,
                   generate_preview)
      .release();
}

bool v8_inspector__V8InspectorSession__unwrapObject(
    v8_inspector::V8InspectorSession* self, v8_inspector::StringBuffer** error,
    v8_inspector::StringView object_id, const v8::Value** value,
    const v8::Context** context, v8_inspector::StringBuffer** object_group) {
  std::unique_ptr<v8_inspector::StringBuffer> error_buffer;
  v8::Local<v8::Value> local_value;
  v8::Local<v8::Context> local_context;
  std::unique_ptr<v8_inspector::StringBuffer> object_group_buffer;
  bool success = self->unwrapObject(&error_buffer, object_id, &local_value,
                                    &local_context, &object_group_buffer);
  if (!success) {
    *error = error_buffer.release();
    return false;
  }

  *value = local_to_ptr(local_value);
  *context = local_to_ptr(local_context);
  *object_group = object_group_buffer.release();
  return true;
}

void v8_inspector__RemoteObject__DELETE(
    v8_inspector::protocol::Runtime::API::RemoteObject* self) {
  delete self;
}

void v8_inspector__V8InspectorSession__cancelPauseOnNextStatement(
    v8_inspector::V8InspectorSession* self) {
  self->cancelPauseOnNextStatement();
}
}  // extern "C"

extern "C" {
__attribute__((weak)) const v8::Value* v8_inspector__V8InspectorSession__Inspectable__BASE__get(
    void* rust_impl, const v8::Context* context);
__attribute__((weak)) void v8_inspector__V8InspectorSession__Inspectable__BASE__DROP(void* rust_impl);
}

class v8_inspector__V8InspectorSession__Inspectable__BASE final
    : public v8_inspector::V8InspectorSession::Inspectable {
 public:
  explicit v8_inspector__V8InspectorSession__Inspectable__BASE(void* rust_impl)
      : rust_impl_(rust_impl) {}

  ~v8_inspector__V8InspectorSession__Inspectable__BASE() override {
    v8_inspector__V8InspectorSession__Inspectable__BASE__DROP(rust_impl_);
  }

  v8::Local<v8::Value> get(v8::Local<v8::Context> context) override {
    // The Rust CallbackScope relies on `NewCallbackScope for Local<Context>`
    // having `NEEDS_SCOPE == false` and must not open its own HandleScope.
    // Handles created by the Rust implementation are allocated in this scope
    // and must be escaped here. Opening a nested HandleScope in Rust would
    // destroy that scope before Escape uses its handle, causing a
    // use-after-free.
    v8::Isolate* isolate = v8::Isolate::GetCurrent();
    if (isolate == nullptr) return v8::Local<v8::Value>();
    v8::EscapableHandleScope handle_scope(isolate);
    v8::Context::Scope context_scope(context);
    return handle_scope.Escape(
        ptr_to_local(v8_inspector__V8InspectorSession__Inspectable__BASE__get(
            rust_impl_, local_to_ptr(context))));
  }

 private:
  void* rust_impl_;
};

extern "C" {
v8_inspector::V8InspectorSession::Inspectable*
v8_inspector__V8InspectorSession__Inspectable__NEW(void* rust_impl) {
  return new v8_inspector__V8InspectorSession__Inspectable__BASE(rust_impl);
}

void v8_inspector__V8InspectorSession__Inspectable__DELETE(
    v8_inspector::V8InspectorSession::Inspectable* inspectable) {
  delete inspectable;
}

void v8_inspector__V8InspectorSession__addInspectedObject(
    v8_inspector::V8InspectorSession* self,
    v8_inspector::V8InspectorSession::Inspectable* inspectable) {
  self->addInspectedObject(
      std::unique_ptr<v8_inspector::V8InspectorSession::Inspectable>(
          inspectable));
}
}

struct v8_inspector__V8Inspector__Channel__BASE
    : public v8_inspector::V8Inspector::Channel {
  using v8_inspector::V8Inspector::Channel::Channel;

  void sendResponse(
      int callId,
      std::unique_ptr<v8_inspector::StringBuffer> message) override {
    v8_inspector__V8Inspector__Channel__BASE__sendResponse(this, callId,
                                                           message.release());
  }
  void sendNotification(
      std::unique_ptr<v8_inspector::StringBuffer> message) override {
    v8_inspector__V8Inspector__Channel__BASE__sendNotification(
        this, message.release());
  }
  void flushProtocolNotifications() override {
    v8_inspector__V8Inspector__Channel__BASE__flushProtocolNotifications(this);
  }
};

extern "C" {
void v8_inspector__V8Inspector__Channel__BASE__CONSTRUCT(
    uninit_t<v8_inspector__V8Inspector__Channel__BASE>* buf) {
  construct_in_place<v8_inspector__V8Inspector__Channel__BASE>(buf);
}

__attribute__((weak)) int64_t v8_inspector__V8InspectorClient__BASE__generateUniqueId(
    v8_inspector::V8InspectorClient* self);
__attribute__((weak)) void v8_inspector__V8InspectorClient__BASE__runMessageLoopOnPause(
    v8_inspector::V8InspectorClient* self, int contextGroupId);
__attribute__((weak)) void v8_inspector__V8InspectorClient__BASE__quitMessageLoopOnPause(
    v8_inspector::V8InspectorClient* self);
__attribute__((weak)) void v8_inspector__V8InspectorClient__BASE__runIfWaitingForDebugger(
    v8_inspector::V8InspectorClient* self, int contextGroupId);
__attribute__((weak)) void v8_inspector__V8InspectorClient__BASE__consoleAPIMessage(
    v8_inspector::V8InspectorClient* self, int contextGroupId,
    v8::Isolate::MessageErrorLevel level,
    const v8_inspector::StringView& message,
    const v8_inspector::StringView& url, unsigned lineNumber,
    unsigned columnNumber, v8_inspector::V8StackTrace* stackTrace);
__attribute__((weak)) v8_inspector::StringBuffer* v8_inspector__V8InspectorClient__BASE__valueSubtype(
    v8_inspector::V8InspectorClient* self, v8::Context* context,
    v8::Value* value);
__attribute__((weak)) v8_inspector::StringBuffer*
v8_inspector__V8InspectorClient__BASE__descriptionForValueSubtype(
    v8_inspector::V8InspectorClient* self, v8::Context* context,
    v8::Value* value);
__attribute__((weak)) v8::Context* v8_inspector__V8InspectorClient__BASE__ensureDefaultContextInGroup(
    v8_inspector::V8InspectorClient* self, int context_group_id);
__attribute__((weak)) v8_inspector::StringBuffer*
v8_inspector__V8InspectorClient__BASE__resourceNameToUrl(
    v8_inspector::V8InspectorClient* self,
    const v8_inspector::StringView& resource_name_view);

}  // extern "C"

struct v8_inspector__V8InspectorClient__BASE
    : public v8_inspector::V8InspectorClient {
  using v8_inspector::V8InspectorClient::V8InspectorClient;

  int64_t generateUniqueId() override {
    return v8_inspector__V8InspectorClient__BASE__generateUniqueId(this);
  }
  void runMessageLoopOnPause(int contextGroupId) override {
    v8_inspector__V8InspectorClient__BASE__runMessageLoopOnPause(
        this, contextGroupId);
  }
  void quitMessageLoopOnPause() override {
    v8_inspector__V8InspectorClient__BASE__quitMessageLoopOnPause(this);
  }
  void runIfWaitingForDebugger(int contextGroupId) override {
    v8_inspector__V8InspectorClient__BASE__runIfWaitingForDebugger(
        this, contextGroupId);
  }
  void consoleAPIMessage(int contextGroupId,
                         v8::Isolate::MessageErrorLevel level,
                         const v8_inspector::StringView& message,
                         const v8_inspector::StringView& url,
                         unsigned lineNumber, unsigned columnNumber,
                         v8_inspector::V8StackTrace* stackTrace) override {
    v8_inspector__V8InspectorClient__BASE__consoleAPIMessage(
        this, contextGroupId, level, message, url, lineNumber, columnNumber,
        stackTrace);
  }
  std::unique_ptr<v8_inspector::StringBuffer> valueSubtype(
      v8::Local<v8::Value> value) override {
    v8::Isolate* isolate = v8::Isolate::GetCurrent();
    if (isolate == nullptr) return nullptr;
    v8::Local<v8::Context> context = isolate->GetCurrentContext();
    if (context.IsEmpty()) return nullptr;
    v8_inspector::StringBuffer* b =
        v8_inspector__V8InspectorClient__BASE__valueSubtype(
            this, local_to_ptr(context), local_to_ptr(value));
    return std::unique_ptr<v8_inspector::StringBuffer>(b);
  }
  std::unique_ptr<v8_inspector::StringBuffer> descriptionForValueSubtype(
      v8::Local<v8::Context> context, v8::Local<v8::Value> value) override {
    v8_inspector::StringBuffer* b =
        v8_inspector__V8InspectorClient__BASE__descriptionForValueSubtype(
            this, local_to_ptr(context), local_to_ptr(value));
    return std::unique_ptr<v8_inspector::StringBuffer>(b);
  }
  v8::Local<v8::Context> ensureDefaultContextInGroup(
      int context_group_id) override {
    return ptr_to_local(
        v8_inspector__V8InspectorClient__BASE__ensureDefaultContextInGroup(
            this, context_group_id));
  }
  std::unique_ptr<v8_inspector::StringBuffer> resourceNameToUrl(
      const v8_inspector::StringView& resource_name_view) override {
    v8_inspector::StringBuffer* b =
        v8_inspector__V8InspectorClient__BASE__resourceNameToUrl(
            this, resource_name_view);
    return std::unique_ptr<v8_inspector::StringBuffer>(b);
  }
};

extern "C" {
void v8_inspector__V8InspectorClient__BASE__CONSTRUCT(
    uninit_t<v8_inspector__V8InspectorClient__BASE>* buf) {
  construct_in_place<v8_inspector__V8InspectorClient__BASE>(buf);
}

}  // extern "C"

// ---- CRDTP (cargo feature `inspector`), from denoland/rusty_v8 src/crdtp_binding.cc ----

using namespace support;
using namespace v8_crdtp;

extern "C" {
__attribute__((weak)) void crdtp__FrontendChannel__BASE__sendProtocolResponse(FrontendChannel* self,
                                                        int call_id,
                                                        Serializable* message);
__attribute__((weak)) void crdtp__FrontendChannel__BASE__sendProtocolNotification(
    FrontendChannel* self, Serializable* message);
__attribute__((weak)) void crdtp__FrontendChannel__BASE__flushProtocolNotifications(
    FrontendChannel* self);
__attribute__((weak)) void crdtp__FallthroughCallback__Run(
    void* callback, int call_id, const uint8_t* method_data, size_t method_len,
    const uint8_t* message_data, size_t message_len,
    const uint8_t* associated_data, size_t associated_data_len);
__attribute__((weak)) void crdtp__FallthroughCallback__Drop(void* callback);
}  // extern "C"

struct crdtp__FrontendChannel__BASE : public FrontendChannel {
  void SendProtocolResponse(int call_id,
                            std::unique_ptr<Serializable> message) override {
    crdtp__FrontendChannel__BASE__sendProtocolResponse(this, call_id,
                                                       message.release());
  }
  void SendProtocolNotification(
      std::unique_ptr<Serializable> message) override {
    crdtp__FrontendChannel__BASE__sendProtocolNotification(this,
                                                           message.release());
  }
  void FlushProtocolNotifications() override {
    crdtp__FrontendChannel__BASE__flushProtocolNotifications(this);
  }
};

static_assert(sizeof(crdtp__FrontendChannel__BASE) <= sizeof(void*),
              "FrontendChannel BASE must fit in a single vtable pointer");

extern "C" {

void crdtp__FrontendChannel__BASE__CONSTRUCT(
    uninit_t<crdtp__FrontendChannel__BASE>* buf) {
  construct_in_place<crdtp__FrontendChannel__BASE>(buf);
}

void crdtp__Serializable__DELETE(Serializable* self) { delete self; }

// Serialize once into a caller-provided CppVecU8 to avoid double-serialization.
void crdtp__Serializable__AppendSerialized(const Serializable* self,
                                           std::vector<uint8_t>* out) {
  self->AppendSerialized(out);
}

Dispatchable* crdtp__Dispatchable__new(const uint8_t* data, size_t len,
                                       const uint8_t* associated_data,
                                       size_t associated_data_len,
                                       void* rust_callback) {
  FallthroughCallback fallthrough_callback;
  if (rust_callback) {
    auto callback =
        std::shared_ptr<void>(rust_callback, crdtp__FallthroughCallback__Drop);
    fallthrough_callback = [callback](
                               int call_id, span<uint8_t> method,
                               span<uint8_t> serialized_message,
                               std::string_view fallthrough_associated_data) {
      crdtp__FallthroughCallback__Run(
          callback.get(), call_id, method.data(), method.size(),
          serialized_message.data(), serialized_message.size(),
          reinterpret_cast<const uint8_t*>(fallthrough_associated_data.data()),
          fallthrough_associated_data.size());
    };
  }
  return new Dispatchable(
      span<uint8_t>(data, len),
      std::string_view(reinterpret_cast<const char*>(associated_data),
                       associated_data_len),
      std::move(fallthrough_callback));
}

void crdtp__Dispatchable__DELETE(Dispatchable* self) { delete self; }

bool crdtp__Dispatchable__ok(const Dispatchable* self) { return self->ok(); }

int32_t crdtp__Dispatchable__callId(const Dispatchable* self) {
  return self->CallId();
}

bool crdtp__Dispatchable__hasCallId(const Dispatchable* self) {
  return self->HasCallId();
}

size_t crdtp__Dispatchable__methodLen(const Dispatchable* self) {
  return self->Method().size();
}

void crdtp__Dispatchable__methodCopy(const Dispatchable* self, uint8_t* out) {
  span<uint8_t> method = self->Method();
  memcpy(out, method.data(), method.size());
}

size_t crdtp__Dispatchable__sessionIdLen(const Dispatchable* self) {
  return self->SessionId().size();
}

void crdtp__Dispatchable__sessionIdCopy(const Dispatchable* self,
                                        uint8_t* out) {
  span<uint8_t> session_id = self->SessionId();
  memcpy(out, session_id.data(), session_id.size());
}

size_t crdtp__Dispatchable__paramsLen(const Dispatchable* self) {
  return self->Params().size();
}

void crdtp__Dispatchable__paramsCopy(const Dispatchable* self, uint8_t* out) {
  span<uint8_t> params = self->Params();
  memcpy(out, params.data(), params.size());
}

size_t crdtp__Dispatchable__associatedDataLen(const Dispatchable* self) {
  return self->AssociatedData().size();
}

void crdtp__Dispatchable__associatedDataCopy(const Dispatchable* self,
                                             uint8_t* out) {
  std::string_view associated_data = self->AssociatedData();
  memcpy(out, associated_data.data(), associated_data.size());
}

struct DispatchResponseWrapper {
  DispatchResponse inner;

  explicit DispatchResponseWrapper(DispatchResponse&& r)
      : inner(std::move(r)) {}
};

DispatchResponseWrapper* crdtp__DispatchResponse__Success() {
  return new DispatchResponseWrapper(DispatchResponse::Success());
}

DispatchResponseWrapper* crdtp__DispatchResponse__FallThrough() {
  return new DispatchResponseWrapper(DispatchResponse::FallThrough());
}

DispatchResponseWrapper* crdtp__DispatchResponse__ParseError(const char* msg,
                                                             size_t len) {
  return new DispatchResponseWrapper(
      DispatchResponse::ParseError(std::string(msg, len)));
}

DispatchResponseWrapper* crdtp__DispatchResponse__InvalidRequest(
    const char* msg, size_t len) {
  return new DispatchResponseWrapper(
      DispatchResponse::InvalidRequest(std::string(msg, len)));
}

DispatchResponseWrapper* crdtp__DispatchResponse__MethodNotFound(
    const char* msg, size_t len) {
  return new DispatchResponseWrapper(
      DispatchResponse::MethodNotFound(std::string(msg, len)));
}

DispatchResponseWrapper* crdtp__DispatchResponse__InvalidParams(const char* msg,
                                                                size_t len) {
  return new DispatchResponseWrapper(
      DispatchResponse::InvalidParams(std::string(msg, len)));
}

DispatchResponseWrapper* crdtp__DispatchResponse__ServerError(const char* msg,
                                                              size_t len) {
  return new DispatchResponseWrapper(
      DispatchResponse::ServerError(std::string(msg, len)));
}

void crdtp__DispatchResponse__DELETE(DispatchResponseWrapper* self) {
  delete self;
}

bool crdtp__DispatchResponse__isSuccess(const DispatchResponseWrapper* self) {
  return self->inner.IsSuccess();
}

bool crdtp__DispatchResponse__isError(const DispatchResponseWrapper* self) {
  return self->inner.IsError();
}

bool crdtp__DispatchResponse__isFallThrough(
    const DispatchResponseWrapper* self) {
  return self->inner.IsFallThrough();
}

int crdtp__DispatchResponse__code(const DispatchResponseWrapper* self) {
  return static_cast<int>(self->inner.Code());
}

size_t crdtp__DispatchResponse__messageLen(
    const DispatchResponseWrapper* self) {
  return self->inner.Message().size();
}

void crdtp__DispatchResponse__messageCopy(const DispatchResponseWrapper* self,
                                          char* out) {
  const std::string& msg = self->inner.Message();
  memcpy(out, msg.data(), msg.size());
}

UberDispatcher* crdtp__UberDispatcher__new(FrontendChannel* channel) {
  return new UberDispatcher(channel);
}

void crdtp__UberDispatcher__DELETE(UberDispatcher* self) { delete self; }

FrontendChannel* crdtp__UberDispatcher__channel(UberDispatcher* self) {
  return self->channel();
}

void crdtp__UberDispatcher__Dispatch(UberDispatcher* self,
                                     Dispatchable* dispatchable) {
  self->Dispatch(*dispatchable);
}

// Convert JSON to CBOR
bool crdtp__json__ConvertJSONToCBOR(const uint8_t* json_data, size_t json_len,
                                    std::vector<uint8_t>* cbor_out) {
  json::ConvertJSONToCBOR(span<uint8_t>(json_data, json_len), cbor_out);
  return !cbor_out->empty();
}

// Convert CBOR to JSON
bool crdtp__json__ConvertCBORToJSON(const uint8_t* cbor_data, size_t cbor_len,
                                    std::vector<uint8_t>* json_out) {
  std::string json_str;
  Status status =
      json::ConvertCBORToJSON(span<uint8_t>(cbor_data, cbor_len), &json_str);
  if (!status.ok()) {
    return false;
  }
  json_out->assign(json_str.begin(), json_str.end());
  return true;
}

std::vector<uint8_t>* crdtp__vec_u8__new() {
  return new std::vector<uint8_t>();
}

std::vector<uint8_t>* v8_inspector__RemoteObject__toBytes(
    const v8_inspector::protocol::Runtime::API::RemoteObject* self) {
  auto* bytes = crdtp__vec_u8__new();
  self->AppendSerialized(bytes);
  return bytes;
}

void crdtp__vec_u8__DELETE(std::vector<uint8_t>* self) { delete self; }

size_t crdtp__vec_u8__size(const std::vector<uint8_t>* self) {
  return self->size();
}

void crdtp__vec_u8__copy(const std::vector<uint8_t>* self, uint8_t* out) {
  memcpy(out, self->data(), self->size());
}

Serializable* crdtp__CreateErrorResponse(int call_id,
                                         DispatchResponseWrapper* response) {
  return CreateErrorResponse(call_id, std::move(response->inner)).release();
}

Serializable* crdtp__CreateResponse(int call_id, Serializable* params) {
  std::unique_ptr<Serializable> params_ptr(params);
  return CreateResponse(call_id, std::move(params_ptr)).release();
}

// Owns a copy of the method string, since upstream Notification stores only
// a raw const char* pointer which leads to use-after-free when the Rust
// CString is dropped before AppendSerialized is called.
class OwnedNotification : public Serializable {
 public:
  OwnedNotification(const char* method, std::unique_ptr<Serializable> params)
      : method_(method), params_(std::move(params)) {}

  void AppendSerialized(std::vector<uint8_t>* out) const override {
    Status status;
    std::unique_ptr<ParserHandler> encoder = cbor::NewCBOREncoder(out, &status);
    encoder->HandleMapBegin();
    encoder->HandleString8(SpanFrom("method"));
    encoder->HandleString8(SpanFrom(method_));
    encoder->HandleString8(SpanFrom("params"));
    if (params_) {
      params_->AppendSerialized(out);
    } else {
      encoder->HandleMapBegin();
      encoder->HandleMapEnd();
    }
    encoder->HandleMapEnd();
    assert(status.ok());
  }

 private:
  std::string method_;
  std::unique_ptr<Serializable> params_;
};

Serializable* crdtp__CreateNotification(const char* method,
                                        Serializable* params) {
  std::unique_ptr<Serializable> params_ptr(params);
  return new OwnedNotification(method, std::move(params_ptr));
}

Serializable* crdtp__CreateErrorNotification(
    DispatchResponseWrapper* response) {
  return CreateErrorNotification(std::move(response->inner)).release();
}

}  // extern "C"

// DomainDispatcher binding - allows Rust to implement domain dispatchers.

extern "C" {
// Rust callback: given a domain dispatcher pointer and a command name,
// executes the command and returns whether it was handled.
__attribute__((weak)) bool crdtp__DomainDispatcher__BASE__Dispatch(void* rust_dispatcher,
                                             const uint8_t* command_data,
                                             size_t command_len,
                                             const Dispatchable& dispatchable);
// Rust callback: destroy the Rust DomainDispatcher when C++ side is destroyed.
__attribute__((weak)) void crdtp__DomainDispatcher__BASE__Drop(void* rust_dispatcher);
}

struct crdtp__DomainDispatcher__BASE : public DomainDispatcher {
  void* rust_dispatcher_;

  crdtp__DomainDispatcher__BASE(FrontendChannel* channel, void* rust_dispatcher)
      : DomainDispatcher(channel), rust_dispatcher_(rust_dispatcher) {}

  ~crdtp__DomainDispatcher__BASE() override {
    crdtp__DomainDispatcher__BASE__Drop(rust_dispatcher_);
  }

  bool Dispatch(span<uint8_t> command_name,
                Dispatchable& dispatchable) override {
    return crdtp__DomainDispatcher__BASE__Dispatch(
        rust_dispatcher_, command_name.data(), command_name.size(),
        dispatchable);
  }
};

extern "C" {

crdtp__DomainDispatcher__BASE* crdtp__DomainDispatcher__new(
    FrontendChannel* channel, void* rust_dispatcher) {
  return new crdtp__DomainDispatcher__BASE(channel, rust_dispatcher);
}

void crdtp__DomainDispatcher__sendResponse(crdtp__DomainDispatcher__BASE* self,
                                           int call_id,
                                           DispatchResponseWrapper* response,
                                           Serializable* result) {
  std::unique_ptr<Serializable> result_ptr(result);
  self->sendResponse(call_id, std::move(response->inner),
                     std::move(result_ptr));
  delete response;
}

void crdtp__UberDispatcher__WireBackend(
    UberDispatcher* uber, const uint8_t* domain_data, size_t domain_len,
    crdtp__DomainDispatcher__BASE* dispatcher) {
  std::unique_ptr<DomainDispatcher> dispatcher_ptr(dispatcher);
  uber->WireBackend(span<uint8_t>(domain_data, domain_len),
                    std::vector<std::pair<span<uint8_t>, span<uint8_t>>>(),
                    std::move(dispatcher_ptr));
}

}  // extern "C"
