@DefaultAsset('package:hf_tokenizers/src/bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Void> Function(Pointer<Uint8>, IntPtr)>(symbol: 'tk_from_bytes')
external Pointer<Void> tkFromBytes(Pointer<Uint8> data, int len);

@Native<
    Pointer<Uint32> Function(
        Pointer<Void>, Pointer<Utf8>, Bool, Pointer<IntPtr>)>(symbol: 'tk_encode')
external Pointer<Uint32> tkEncode(
    Pointer<Void> tk, Pointer<Utf8> text, bool addSpecialTokens, Pointer<IntPtr> outLen);

@Native<Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint32>, IntPtr, Bool)>(
    symbol: 'tk_decode')
external Pointer<Utf8> tkDecode(
    Pointer<Void> tk, Pointer<Uint32> ids, int len, bool skipSpecialTokens);

@Native<IntPtr Function(Pointer<Void>)>(symbol: 'tk_vocab_size')
external int tkVocabSize(Pointer<Void> tk);

@Native<Bool Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint32>)>(
    symbol: 'tk_token_to_id')
external bool tkTokenToId(
    Pointer<Void> tk, Pointer<Utf8> token, Pointer<Uint32> outId);

@Native<Pointer<Utf8> Function(Pointer<Void>, Uint32)>(symbol: 'tk_id_to_token')
external Pointer<Utf8> tkIdToToken(Pointer<Void> tk, int id);

@Native<Void Function(Pointer<Uint32>, IntPtr)>(symbol: 'tk_free_ids')
external void tkFreeIds(Pointer<Uint32> ids, int len);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'tk_free_string')
external void tkFreeString(Pointer<Utf8> text);

@Native<Void Function(Pointer<Void>)>(symbol: 'tk_free')
external void tkFree(Pointer<Void> tk);

/// Address of [tkFree], for use as a [NativeFinalizer] callback.
final Pointer<NativeFinalizerFunction> tkFreePtr =
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(tkFree);
