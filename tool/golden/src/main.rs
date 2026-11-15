//! Writes the expected outputs that `test/golden_test.dart` compares the Dart
//! API with.
//!
//! It reads a `tokenizer.json` and a corpus, runs every case through the
//! `tokenizers` crate directly, and writes one JSON object per line. The first
//! line names the crate version from this generator's `Cargo.lock`. Run it from
//! the repository root.
//!
//! ```text
//! cargo run --locked --manifest-path tool/golden/Cargo.toml -- \
//!     test/fixtures/bert-base-uncased.json \
//!     test/golden/corpus.json \
//!     test/golden/bert-base-uncased.jsonl
//! ```

use std::process::ExitCode;

use serde::{Deserialize, Serialize};
use tokenizers::{Encoding, Tokenizer, TruncationParams};

/// One corpus entry. The input is `text` repeated `repeat` times. Each value in
/// `truncate` is a token budget to truncate that input to.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Case {
    name: String,
    text: String,
    #[serde(default = "one")]
    repeat: usize,
    #[serde(default)]
    truncate: Vec<usize>,
}

fn one() -> usize {
    1
}

#[derive(Serialize)]
struct Header<'a> {
    tokenizers: &'a str,
    vocab_size: usize,
}

/// The fields keep the order the Dart test writes them in. Both sides
/// serialize compact JSON, and the test compares the bytes.
#[derive(Serialize)]
struct Encoded<'a> {
    case: &'a str,
    add_special_tokens: bool,
    ids: &'a [u32],
    tokens: &'a [String],
    offsets: &'a [(usize, usize)],
    attention_mask: &'a [u32],
    special_tokens_mask: &'a [u32],
    decode: String,
    decode_keep_special: String,
}

#[derive(Serialize)]
struct Truncated<'a> {
    case: &'a str,
    truncate_to: usize,
    ids: &'a [u32],
    offsets: &'a [(usize, usize)],
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [tokenizer, corpus, output] = args.as_slice() else {
        eprintln!("usage: golden <tokenizer.json> <corpus.json> <output.jsonl>");
        return ExitCode::from(64);
    };
    match run(tokenizer, corpus, output) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("golden: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run(tokenizer: &str, corpus: &str, output: &str) -> Result<(), String> {
    let bytes = std::fs::read(tokenizer).map_err(|e| format!("{tokenizer}: {e}"))?;
    // The Dart side loads through `Tokenizer::from_bytes` as well.
    let tk = Tokenizer::from_bytes(&bytes).map_err(|e| format!("{tokenizer}: {e}"))?;
    let corpus_text = std::fs::read_to_string(corpus).map_err(|e| format!("{corpus}: {e}"))?;
    let cases: Vec<Case> =
        serde_json::from_str(&corpus_text).map_err(|e| format!("{corpus}: {e}"))?;

    let mut lines = vec![to_json(&Header {
        tokenizers: &locked_tokenizers_version()?,
        vocab_size: tk.get_vocab_size(true),
    })?];
    for case in &cases {
        let text = case.text.repeat(case.repeat);
        for add_special_tokens in [true, false] {
            let enc = encode(&tk, &text, add_special_tokens, &case.name)?;
            let decode = |skip: bool| {
                tk.decode(enc.get_ids(), skip)
                    .map_err(|e| format!("{}: decode: {e}", case.name))
            };
            lines.push(to_json(&Encoded {
                case: &case.name,
                add_special_tokens,
                ids: enc.get_ids(),
                tokens: enc.get_tokens(),
                offsets: enc.get_offsets(),
                attention_mask: enc.get_attention_mask(),
                special_tokens_mask: enc.get_special_tokens_mask(),
                decode: decode(true)?,
                decode_keep_special: decode(false)?,
            })?);
        }
        for &max_length in &case.truncate {
            let mut truncating = tk.clone();
            truncating
                .with_truncation(Some(TruncationParams {
                    max_length,
                    ..TruncationParams::default()
                }))
                .map_err(|e| format!("{}: truncate to {max_length}: {e}", case.name))?;
            let enc = encode(&truncating, &text, true, &case.name)?;
            lines.push(to_json(&Truncated {
                case: &case.name,
                truncate_to: max_length,
                ids: enc.get_ids(),
                offsets: enc.get_offsets(),
            })?);
        }
    }

    let mut out = lines.join("\n");
    out.push('\n');
    std::fs::write(output, out).map_err(|e| format!("{output}: {e}"))
}

fn encode(
    tk: &Tokenizer,
    text: &str,
    add_special_tokens: bool,
    name: &str,
) -> Result<Encoding, String> {
    tk.encode(text, add_special_tokens)
        .map_err(|e| format!("{name}: encode: {e}"))
}

fn to_json<T: Serialize>(value: &T) -> Result<String, String> {
    serde_json::to_string(value).map_err(|e| e.to_string())
}

/// The `tokenizers` version in this generator's lock file. With `--locked` it is
/// also the version cargo compiled.
fn locked_tokenizers_version() -> Result<String, String> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.lock");
    let lock = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    let mut lines = lock.lines();
    while let Some(line) = lines.next() {
        if line == r#"name = "tokenizers""# {
            let version = lines
                .next()
                .and_then(|l| l.strip_prefix(r#"version = ""#))
                .and_then(|l| l.strip_suffix('"'));
            if let Some(version) = version {
                return Ok(version.to_string());
            }
        }
    }
    Err(format!("{path}: no tokenizers entry"))
}
