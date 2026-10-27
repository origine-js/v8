//! Build script for the `v8` crate when it sits on top of `this repository (v8_zig)`.
//!
//! Unlike upstream rusty_v8 this never downloads or builds V8: the final link
//! consumes the `libv8_zig.a` archive that `zig build rusty` produces, so Zig and
//! Rust share a single copy of V8. Everything is driven by environment variables
//! exported by the Zig build (`../build/rusty.build.zig`):
//!
//! - `V8_ZIG_ARCHIVE`   absolute path of `libv8_zig.a`
//! - `V8_ZIG_MIMALLOC`  absolute path of `libmimalloc.a`
//! - `V8_ZIG_ICU`       absolute path of `libv8_icu.a` (the ICU data provider link object)
//! - `V8_ZIG_V8_ROOT`   V8 checkout the archive was built from (headers, libc++)
//! - `V8_ZIG_BINDING`   `../binding` (binding.hpp, support.h)
//! - `V8_ZIG_GN_OUT`    GN output directory holding `compile_commands.json`
//!
//! `LIBCLANG_PATH` must point at a libclang >= 21.1 for bindgen.

use std::env;
use std::path::Path;
use std::path::PathBuf;

/// Reads a required environment variable and registers it for rebuilds.
/// Panics with the variable name when missing; retains nothing.
fn required(name: &str) -> String {
  println!("cargo:rerun-if-env-changed={name}");
  env::var(name).unwrap_or_else(|_| {
    panic!("{name} is not set; build through `zig build rusty` in this repository (v8_zig)")
  })
}

/// Extracts the `-D` defines of the shim translation unit from GN's compile
/// commands. The defines select V8's ABI (pointer compression, sandbox, direct
/// handles, cppgc caged heap...), so bindgen must see exactly what V8 was built
/// with. Borrows the path; returns owned strings.
fn v8_defines(gn_out: &Path) -> Vec<String> {
  let path = gn_out.join("compile_commands.json");
  println!("cargo:rerun-if-changed={}", path.display());
  let text = std::fs::read_to_string(&path)
    .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
  let entries: serde_json::Value =
    serde_json::from_str(&text).expect("compile_commands.json is not JSON");
  let command = entries
    .as_array()
    .unwrap()
    .iter()
    .find(|e| {
      e["file"]
        .as_str()
        .is_some_and(|f| f.ends_with("zig/binding/binding.cc"))
    })
    .and_then(|e| e["command"].as_str())
    .expect("binding.cc not found in compile_commands.json");
  shell_split(command)
    .into_iter()
    .filter(|a| a.starts_with("-D"))
    .collect()
}

/// Minimal POSIX-ish word splitter for GN command lines (handles `"..."` and
/// backslash escapes). Borrows the input; returns owned words.
fn shell_split(s: &str) -> Vec<String> {
  let mut words = Vec::new();
  let mut cur = String::new();
  let mut in_word = false;
  let mut quote = false;
  let mut chars = s.chars();
  while let Some(c) = chars.next() {
    match c {
      '\\' => {
        if let Some(n) = chars.next() {
          cur.push(n);
          in_word = true;
        }
      }
      '"' => {
        quote = !quote;
        in_word = true;
      }
      c if c.is_whitespace() && !quote => {
        if in_word {
          words.push(std::mem::take(&mut cur));
          in_word = false;
        }
      }
      c => {
        cur.push(c);
        in_word = true;
      }
    }
  }
  if in_word {
    words.push(cur);
  }
  words
}

/// Borrows build paths through return; writes generated ABI declarations into
/// Cargo-owned OUT_DIR. Panics on parse/write failure and retains no input paths.
fn build_binding(root: &Path, binding_dir: &Path, gn_out: &Path) {
  if env::var("LIBCLANG_PATH").is_err() {
    println!(
      "cargo:warning=LIBCLANG_PATH is not set; bindgen needs libclang >= 21.1"
    );
  }

  let r = |p: &str| root.join(p).display().to_string();
  let mut clang_args = vec![
    "-x".to_string(),
    "c++".to_string(),
    "-std=c++20".to_string(),
    "-nostdinc++".to_string(),
    format!("-I{}", r("include")),
    format!("-I{}", binding_dir.display()),
    format!("-isystem{}", r("buildtools/third_party/libc++")),
    format!("-isystem{}", r("third_party/libc++/src/include")),
    format!("-isystem{}", r("third_party/libc++abi/src/include")),
  ];

  match env::var("CARGO_CFG_TARGET_OS").unwrap().as_str() {
    "macos" => {
      let output = std::process::Command::new("xcrun")
        .args(["--show-sdk-path"])
        .output()
        .unwrap();
      clang_args.push("-isysroot".to_string());
      clang_args.push(String::from_utf8(output.stdout).unwrap().trim().into());
    }
    "linux" => {
      if let Ok(dir) = env::var("RUSTY_V8_BINDGEN_RESOURCE_DIR") {
        clang_args.push(format!("-resource-dir={dir}"));
      }
    }
    _ => {}
  }
  clang_args.extend(v8_defines(gn_out));

  let header = binding_dir.join("binding.hpp");
  println!("cargo:rerun-if-changed={}", header.display());
  println!(
    "cargo:rerun-if-changed={}",
    binding_dir.join("support.h").display()
  );

  let bindings = bindgen::Builder::default()
    .header(header.display().to_string())
    .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
    .clang_args(clang_args)
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
    .generate()
    .expect("Unable to generate bindings");

  let out_path =
    PathBuf::from(env::var("OUT_DIR").unwrap()).join("src_binding.rs");
  println!(
    "cargo:rustc-env=RUSTY_V8_SRC_BINDING_PATH={}",
    out_path.display()
  );
  bindings
    .write_to_file(out_path)
    .expect("Couldn't write bindings!");
}

/// Emits link directives for the Zig-built archives. V8 carries its own libc++
/// (`std::__Cr`), so no C++ standard library is linked here.
fn print_link_flags(archive: &Path, mimalloc: &Path, icu: &Path) {
  for p in [archive, mimalloc, icu] {
    println!("cargo:rerun-if-changed={}", p.display());
    println!(
      "cargo:rustc-link-search=native={}",
      p.parent().unwrap().display()
    );
  }
  let stem = |p: &Path| {
    let n = p.file_stem().unwrap().to_str().unwrap();
    n.strip_prefix("lib").unwrap_or(n).to_string()
  };
  // `-bundle`: never copy the archives into a consuming staticlib/rlib. The
  // final link (Zig) supplies V8, mimalloc and the ICU provider exactly once; `rusty_v8`'s own
  // binaries/tests get them through these directives as before.
  println!("cargo:rustc-link-lib=static:-bundle={}", stem(archive));
  println!("cargo:rustc-link-lib=static:-bundle={}", stem(mimalloc));
  // After the archive: it references the provider's `v8_zig_icu_initialize`.
  println!("cargo:rustc-link-lib=static:-bundle={}", stem(icu));

  match env::var("CARGO_CFG_TARGET_OS").unwrap().as_str() {
    "macos" | "ios" => {
      // Frameworks are loaded lazily by the archive (darwin-frameworks.cc).
      println!("cargo:rustc-link-lib=dylib=System");
    }
    "linux" | "android" => {
      println!("cargo:rustc-link-lib=dylib=pthread");
      println!("cargo:rustc-link-lib=dylib=dl");
    }
    _ => {}
  }
}

fn main() {
  println!("cargo:rerun-if-changed=build.rs");
  let archive = PathBuf::from(required("V8_ZIG_ARCHIVE"));
  let mimalloc = PathBuf::from(required("V8_ZIG_MIMALLOC"));
  let icu = PathBuf::from(required("V8_ZIG_ICU"));
  let root = PathBuf::from(required("V8_ZIG_V8_ROOT"));
  let binding_dir = PathBuf::from(required("V8_ZIG_BINDING"));
  let gn_out = PathBuf::from(required("V8_ZIG_GN_OUT"));

  print_link_flags(&archive, &mimalloc, &icu);
  build_binding(&root, &binding_dir, &gn_out);
}
