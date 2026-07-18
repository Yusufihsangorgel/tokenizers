// Loads a tokenizer.json and shows byte-exact encode/decode.
// Run: dart run example/hf_tokenizers_example.dart
import 'package:hf_tokenizers/hf_tokenizers.dart';

void main() {
  final tk = Tokenizer.fromFile('test/fixtures/bert-base-uncased.json');
  print('vocab size: ${tk.vocabSize}');

  const text = 'hello world';
  final ids = tk.encode(text);
  print('encode("$text") -> $ids');       // [101, 7592, 2088, 102]
  print('decode($ids) -> "${tk.decode(ids)}"');

  tk.close();
}
