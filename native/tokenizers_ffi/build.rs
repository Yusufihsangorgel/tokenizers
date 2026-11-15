//! Link settings for the shared library.

fn main() {
    // `dart run` and `dart test` copy the library to `.dart_tool/lib/` and set
    // its install name to that absolute path with `install_name_tool`. The new
    // name has to fit in the spare room of the Mach-O header, and without this
    // flag the linker leaves almost none. The v0.5.0 macOS binaries had 48
    // bytes, and any path longer than 175 bytes failed the build.
    if std::env::var("CARGO_CFG_TARGET_VENDOR").as_deref() == Ok("apple") {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-headerpad_max_install_names");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
