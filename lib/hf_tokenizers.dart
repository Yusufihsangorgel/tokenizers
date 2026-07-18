/// HuggingFace tokenizers for Dart, over FFI.
///
/// Load any model's `tokenizer.json` with [Tokenizer.fromFile] or
/// [Tokenizer.fromBytes], then [Tokenizer.encode] text to token ids and
/// [Tokenizer.decode] them back. The ids are byte-exact with the reference
/// Rust implementation, so they match what the model was trained on.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

/// A tokenizer loaded from a HuggingFace `tokenizer.json`.
///
/// Backed by the Rust `tokenizers` crate, so every normalizer, pre-tokenizer,
/// model (BPE, byte-level BPE, WordPiece, Unigram), and post-processor in the
/// file is applied exactly as the reference does.
class Tokenizer implements Finalizable {
  Tokenizer._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  final Pointer<Void> _handle;
  static final NativeFinalizer _finalizer = NativeFinalizer(tkFreePtr);
  bool _closed = false;

  /// Loads a tokenizer from the raw bytes of a `tokenizer.json`.
  ///
  /// Throws [FormatException] if the bytes are not a valid tokenizer.
  factory Tokenizer.fromBytes(Uint8List json) {
    final buffer = calloc<Uint8>(json.length);
    buffer.asTypedList(json.length).setAll(0, json);
    final handle = tkFromBytes(buffer, json.length);
    calloc.free(buffer);
    if (handle == nullptr) {
      throw const FormatException('Not a valid tokenizer.json');
    }
    return Tokenizer._(handle);
  }

  /// Loads a tokenizer from a `tokenizer.json` file on disk.
  factory Tokenizer.fromFile(String path) =>
      Tokenizer.fromBytes(File(path).readAsBytesSync());

  /// The vocabulary size, including any added tokens.
  int get vocabSize {
    _ensureOpen();
    return tkVocabSize(_handle);
  }

  /// Encodes [text] into token ids.
  ///
  /// [addSpecialTokens] controls whether the model's special tokens (such as
  /// BERT's `[CLS]`/`[SEP]`) are added, matching the reference default of true.
  List<int> encode(String text, {bool addSpecialTokens = true}) {
    _ensureOpen();
    final input = text.toNativeUtf8(allocator: calloc);
    final outLen = calloc<IntPtr>();
    try {
      final ptr = tkEncode(_handle, input, addSpecialTokens, outLen);
      if (ptr == nullptr) throw StateError('Failed to encode text');
      final ids = ptr.asTypedList(outLen.value).toList();
      tkFreeIds(ptr, outLen.value);
      return ids;
    } finally {
      calloc.free(input);
      calloc.free(outLen);
    }
  }

  /// Decodes token [ids] back into text.
  String decode(List<int> ids, {bool skipSpecialTokens = true}) {
    _ensureOpen();
    final array = calloc<Uint32>(ids.length);
    array.asTypedList(ids.length).setAll(0, ids);
    try {
      final ptr = tkDecode(_handle, array, ids.length, skipSpecialTokens);
      if (ptr == nullptr) throw StateError('Failed to decode ids');
      final text = ptr.toDartString();
      tkFreeString(ptr);
      return text;
    } finally {
      calloc.free(array);
    }
  }

  /// Frees the native tokenizer now.
  ///
  /// Optional: a finalizer releases it when this object is collected. Call
  /// [close] to return the native memory promptly when you are done.
  void close() {
    if (_closed) return;
    _closed = true;
    _finalizer.detach(this);
    tkFree(_handle);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Tokenizer has been closed');
  }
}
