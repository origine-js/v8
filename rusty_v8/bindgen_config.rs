// The bindgen options of `src/binding.rs`, shared by `build.rs` (Cargo) and `bindgen_main.rs` (the
// Bazel tool, //lib/v8_zig/rusty_v8:bindgen), so both builds generate the same bindings. The caller
// supplies the header and the clang arguments of the shim's compilation.

/// Borrows nothing; returns the builder with the binding's options added.
fn configure(builder: bindgen::Builder) -> bindgen::Builder {
  builder
    // libc++ 24 implements the deprecated, unused std::aligned_union through a
    // recursive union that panics bindgen's layout traversal. No public V8 or
    // shim declaration uses this trait. Omit only its definition while parsing;
    // native C++ compilation still sees the unmodified matching libc++ headers.
    .clang_arg("-D_LIBCPP___TYPE_TRAITS_ALIGNED_UNION_H")
    .generate_cstr(true)
    .rustified_enum(".*UseCounterFeature")
    .rustified_enum(".*ModuleImportPhase")
    .rustified_enum(".*Intercepted")
    .bitfield_enum(".*GCType")
    .bitfield_enum(".*GCCallbackFlags")
    .allowlist_item("v8__.*")
    .allowlist_item("cppgc__.*")
    .allowlist_item("RustObj")
    .allowlist_item("memory_span_t")
    .allowlist_item("const_memory_span_t")
    .allowlist_item("ExternalConstOneByteStringResource")
    .blocklist_item("cppgc.*Visitor")
    .blocklist_item("RustObj.*Trace")
}
