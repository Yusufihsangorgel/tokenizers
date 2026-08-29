//! Crate-level `encode` vs `encode_fast` on the BERT fixture.
//!
//! `encode_fast` is documented as not computing offsets. This measures whether
//! that skip is visible on WordPiece, independent of Dart/FFI.
//!
//!   cargo run --release --example count_bench
//!
//! Run from `native/tokenizers_ffi/`.

use std::time::Instant;
use tokenizers::Tokenizer;

fn main() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../test/fixtures/bert-base-uncased.json",
    );
    let tk = Tokenizer::from_file(path).expect("load BERT fixture");

    let short = "hello world";
    let prompt = "Summarise the following support thread for an engineer on call. Keep the \
customer's account id, the error codes, and the timestamps. Drop the \
pleasantries. If the thread contains a stack trace, keep only the top frame: \
NoSuchMethodError: 'call' on null at package:acme/sync.dart:412:9.";
    let long = "The naïve café in São Paulo. ".repeat(200);

    for (name, text) in [
        ("short", short.to_string()),
        ("prompt", prompt.to_string()),
        ("long", long),
    ] {
        let n_encode = tk.encode(text.as_str(), true).unwrap().get_ids().len();
        let n_fast = tk.encode_fast(text.as_str(), true).unwrap().get_ids().len();
        assert_eq!(n_encode, n_fast, "{name}: encode and encode_fast disagree");

        for _ in 0..50 {
            let _ = tk.encode(text.as_str(), true).unwrap();
            let _ = tk.encode_fast(text.as_str(), true).unwrap();
        }

        const ROUNDS: u32 = 400;
        let encode_ns = time(ROUNDS, || {
            let _ = tk.encode(text.as_str(), true).unwrap();
        });
        let fast_ns = time(ROUNDS, || {
            let _ = tk.encode_fast(text.as_str(), true).unwrap();
        });
        let ratio = encode_ns as f64 / fast_ns as f64;
        println!(
            "{name}: {n_encode} tokens, {ROUNDS} rounds\n  \
             encode      {:>8} ns/call\n  \
             encode_fast {:>8} ns/call\n  \
             encode / encode_fast: {ratio:.2}x",
            encode_ns, fast_ns
        );
    }
}

fn time(rounds: u32, mut f: impl FnMut()) -> u128 {
    let start = Instant::now();
    for _ in 0..rounds {
        f();
    }
    start.elapsed().as_nanos() / rounds as u128
}
