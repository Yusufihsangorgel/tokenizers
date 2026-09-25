@DefaultAsset('package:hf_tokenizers/src/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Loads a tokenizer from [len] bytes at [data].
///
/// Returns null when the bytes are not valid tokenizer JSON. Release a
/// returned pointer with [tkFree].
@Native<Pointer<Void> Function(Pointer<Uint8>, IntPtr)>(symbol: 'tk_from_bytes')
external Pointer<Void> tkFromBytes(Pointer<Uint8> data, int len);

/// Encodes [textLen] UTF-8 bytes at [text] and writes the id count to [outLen].
///
/// Returns a native id array, or null on failure. Release a returned array
/// with [tkFreeIds], passing the count written to [outLen].
@Native<
  Pointer<Uint32> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    IntPtr,
    Bool,
    Pointer<IntPtr>,
  )
>(symbol: 'tk_encode')
external Pointer<Uint32> tkEncode(
  Pointer<Void> tk,
  Pointer<Uint8> text,
  int textLen,
  bool addSpecialTokens,
  Pointer<IntPtr> outLen,
);

/// Encodes and returns the offsets array (`2 * outLen` `u32`s); writes the ids
/// array pointer to [outIds] and the token count to [outLen]. [text] is passed
/// as [textLen] UTF-8 bytes. Both arrays are freed with [tkFreeIds] (offsets
/// length is `2 * outLen`).
@Native<
  Pointer<Uint32> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    IntPtr,
    Bool,
    Pointer<IntPtr>,
    Pointer<Pointer<Uint32>>,
  )
>(symbol: 'tk_encode_offsets')
external Pointer<Uint32> tkEncodeOffsets(
  Pointer<Void> tk,
  Pointer<Uint8> text,
  int textLen,
  bool addSpecialTokens,
  Pointer<IntPtr> outLen,
  Pointer<Pointer<Uint32>> outIds,
);

/// Decodes [len] ids and returns an owned UTF-8 string, or null on failure.
///
/// Release a returned string with [tkFreeString].
@Native<Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint32>, IntPtr, Bool)>(
  symbol: 'tk_decode',
)
external Pointer<Utf8> tkDecode(
  Pointer<Void> tk,
  Pointer<Uint32> ids,
  int len,
  bool skipSpecialTokens,
);

/// Returns the vocabulary size, including added tokens.
@Native<IntPtr Function(Pointer<Void>)>(symbol: 'tk_vocab_size')
external int tkVocabSize(Pointer<Void> tk);

/// Looks up a token from [tokenLen] UTF-8 bytes and writes its id to [outId].
///
/// Returns false when no id is available.
@Native<Bool Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Pointer<Uint32>)>(
  symbol: 'tk_token_to_id',
)
external bool tkTokenToId(
  Pointer<Void> tk,
  Pointer<Uint8> token,
  int tokenLen,
  Pointer<Uint32> outId,
);

/// Looks up [id] and returns an owned UTF-8 string, or null when absent.
///
/// Release a returned string with [tkFreeString].
@Native<Pointer<Utf8> Function(Pointer<Void>, Uint32)>(symbol: 'tk_id_to_token')
external Pointer<Utf8> tkIdToToken(Pointer<Void> tk, int id);

/// Releases an id or offset array of [len] elements returned by an encode call.
@Native<Void Function(Pointer<Uint32>, IntPtr)>(symbol: 'tk_free_ids')
external void tkFreeIds(Pointer<Uint32> ids, int len);

/// Releases a string returned by [tkDecode] or [tkIdToToken].
@Native<Void Function(Pointer<Utf8>)>(symbol: 'tk_free_string')
external void tkFreeString(Pointer<Utf8> text);

/// Releases a tokenizer pointer returned by [tkFromBytes].
@Native<Void Function(Pointer<Void>)>(symbol: 'tk_free')
external void tkFree(Pointer<Void> tk);

/// Address of [tkFree], for use as a [NativeFinalizer] callback.
final Pointer<NativeFinalizerFunction> tkFreePtr =
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(tkFree);
