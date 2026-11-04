//! `bindgen <header> <out.rs> [clang args...]`: generates `src/binding.rs`'s bindings for the Bazel
//! build. The clang arguments are those of the shim's own compilation (build/bazel/bindgen.bzl);
//! libclang is found through LIBCLANG_PATH.

include!("bindgen_config.rs");

/// Reads the process arguments, writes the bindings to `<out.rs>` and exits; retains nothing.
/// Exits 2 on bad usage and 1 when bindgen or the write fails (the output may then be partial).
fn main() {
  let mut args = std::env::args().skip(1);
  let (Some(header), Some(out)) = (args.next(), args.next()) else {
    eprintln!("usage: bindgen <header> <out.rs> [clang args...]");
    std::process::exit(2);
  };
  let bindings = configure(bindgen::Builder::default().header(header).clang_args(args))
    .generate()
    .unwrap_or_else(|error| {
      eprintln!("bindgen: {error}");
      std::process::exit(1);
    });
  bindings.write_to_file(&out).unwrap_or_else(|error| {
    eprintln!("bindgen: cannot write {out}: {error}");
    std::process::exit(1);
  });
}
