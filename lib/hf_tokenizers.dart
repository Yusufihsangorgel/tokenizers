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

/// One token from [Tokenizer.encodeWithOffsets]: its [id] and the `[start, end)`
/// span of the input it came from.
///
/// [start] and [end] are **byte** offsets into the UTF-8 encoding of the input,
/// matching what the underlying `tokenizers` crate reports. For ASCII text a
/// byte offset equals a character index, but for anything else it does not, so
/// slice the UTF-8 bytes rather than calling `String.substring` (which counts
/// UTF-16 units):
///
/// ```dart
/// final bytes = utf8.encode(text);
/// final piece = utf8.decode(bytes.sublist(token.start, token.end));
/// ```
///
/// This is what token-accurate chunking and span highlighting need. A special
/// token added by the model (such as `[CLS]`) has an empty span where
/// `start == end`.
class TokenOffset {
  /// Creates a token offset.
  const TokenOffset(this.id, this.start, this.end);

  /// The token id, the same value [Tokenizer.encode] would return in this
  /// position.
  final int id;

  /// The start byte offset of this token in the UTF-8 input (inclusive).
  final int start;

  /// The end byte offset of this token in the UTF-8 input (exclusive).
  final int end;

  @override
  String toString() => 'TokenOffset($id, $start..$end)';
}

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

  /// The id of a single [token] string, or null if it is not in the vocabulary.
  ///
  /// Useful for finding a model's special tokens, for example
  /// `tokenToId('[CLS]')`, without encoding a whole string.
  int? tokenToId(String token) {
    _ensureOpen();
    final input = token.toNativeUtf8(allocator: calloc);
    final outId = calloc<Uint32>();
    try {
      final found = tkTokenToId(_handle, input, outId);
      return found ? outId.value : null;
    } finally {
      calloc.free(input);
      calloc.free(outId);
    }
  }

  /// The token string for a single [id], or null if it is not in the
  /// vocabulary.
  ///
  /// This is the inverse of [tokenToId]. Unlike [decode], it returns the raw
  /// token, including any sub-word markers the model uses (such as WordPiece's
  /// `##` prefix), rather than a detokenized piece of text.
  String? idToToken(int id) {
    _ensureOpen();
    final ptr = tkIdToToken(_handle, id);
    if (ptr == nullptr) return null;
    final token = ptr.toDartString();
    tkFreeString(ptr);
    return token;
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

  /// Encodes [text] into tokens, keeping each token's byte span in the input.
  ///
  /// Like [encode], but every token comes back as a [TokenOffset] carrying the
  /// `[start, end)` UTF-8 byte range it was produced from, so you can map tokens
  /// back to the text (see [TokenOffset] for how to slice with those offsets).
  /// This is what token-accurate chunking, span highlighting and named-entity
  /// extraction need. [addSpecialTokens] behaves as in [encode].
  List<TokenOffset> encodeWithOffsets(String text,
      {bool addSpecialTokens = true}) {
    _ensureOpen();
    final input = text.toNativeUtf8(allocator: calloc);
    final outLen = calloc<IntPtr>();
    final outIds = calloc<Pointer<Uint32>>();
    try {
      final offsetsPtr =
          tkEncodeOffsets(_handle, input, addSpecialTokens, outLen, outIds);
      if (offsetsPtr == nullptr) throw StateError('Failed to encode text');
      final count = outLen.value;
      final idsPtr = outIds.value;
      final ids = idsPtr.asTypedList(count);
      final offsets = offsetsPtr.asTypedList(count * 2);
      final result = [
        for (var i = 0; i < count; i++)
          TokenOffset(ids[i], offsets[i * 2], offsets[i * 2 + 1]),
      ];
      tkFreeIds(idsPtr, count);
      tkFreeIds(offsetsPtr, count * 2);
      return result;
    } finally {
      calloc.free(input);
      calloc.free(outLen);
      calloc.free(outIds);
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
