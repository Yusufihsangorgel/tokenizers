// Smoke test: load the built Rust FFI lib directly, tokenize with a real
// tokenizer.json, and check the ids are byte-exact vs HuggingFace.
// Run: dart run tool/ffi_smoke.dart
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _FromBytesC = Pointer<Void> Function(Pointer<Uint8>, IntPtr);
typedef _FromBytes = Pointer<Void> Function(Pointer<Uint8>, int);
typedef _EncodeC = Pointer<Uint32> Function(
    Pointer<Void>, Pointer<Utf8>, Bool, Pointer<IntPtr>);
typedef _Encode = Pointer<Uint32> Function(
    Pointer<Void>, Pointer<Utf8>, bool, Pointer<IntPtr>);
typedef _DecodeC = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Uint32>, IntPtr, Bool);
typedef _Decode = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Uint32>, int, bool);
typedef _FreeIdsC = Void Function(Pointer<Uint32>, IntPtr);
typedef _FreeIds = void Function(Pointer<Uint32>, int);
typedef _FreeStrC = Void Function(Pointer<Utf8>);
typedef _FreeStr = void Function(Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _VocabC = IntPtr Function(Pointer<Void>);
typedef _Vocab = int Function(Pointer<Void>);

void main() {
  final lib = DynamicLibrary.open(
      'native/tokenizers_ffi/target/release/libtokenizers_ffi.dylib');
  final fromBytes = lib.lookupFunction<_FromBytesC, _FromBytes>('tk_from_bytes');
  final encode = lib.lookupFunction<_EncodeC, _Encode>('tk_encode');
  final decode = lib.lookupFunction<_DecodeC, _Decode>('tk_decode');
  final freeIds = lib.lookupFunction<_FreeIdsC, _FreeIds>('tk_free_ids');
  final freeStr = lib.lookupFunction<_FreeStrC, _FreeStr>('tk_free_string');
  final freeTk = lib.lookupFunction<_FreeC, _Free>('tk_free');
  final vocab = lib.lookupFunction<_VocabC, _Vocab>('tk_vocab_size');

  final bytes = File('test/fixtures/bert-base-uncased.json').readAsBytesSync();
  final buf = calloc<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  final tk = fromBytes(buf, bytes.length);
  calloc.free(buf);
  if (tk == nullptr) {
    stderr.writeln('FAIL: could not load tokenizer');
    exit(1);
  }
  stdout.writeln('vocab size: ${vocab(tk)}');

  final text = 'hello world'.toNativeUtf8(allocator: calloc);
  final outLen = calloc<IntPtr>();
  final idsPtr = encode(tk, text, true, outLen);
  final n = outLen.value;
  final ids = [for (var i = 0; i < n; i++) idsPtr[i]];
  stdout.writeln('encode("hello world", special=true) -> $ids');

  final decoded = decode(tk, idsPtr, n, true);
  stdout.writeln('decode -> "${decoded.toDartString()}"');

  const expected = [101, 7592, 2088, 102]; // [CLS] hello world [SEP]
  final ok = ids.length == expected.length &&
      List.generate(n, (i) => ids[i] == expected[i]).every((b) => b);
  stdout.writeln(ok
      ? 'PASS: token ids are byte-exact vs HuggingFace'
      : 'MISMATCH: expected $expected');

  freeStr(decoded);
  freeIds(idsPtr, n);
  calloc.free(text);
  calloc.free(outLen);
  freeTk(tk);
  exit(ok ? 0 : 1);
}
