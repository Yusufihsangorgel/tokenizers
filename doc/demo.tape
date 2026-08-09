# Records doc/demo.gif: the example, run for real, showing whatever it prints.
#
#   dart run example/hf_tokenizers_example.dart   # warm the build hooks first
#   vhs doc/demo.tape
#
# The typing and the wait are hidden so the frame shows the finished screen.
# Wait+Screen keys on the last line the example prints, which is why a cold
# build hook or a busy pub cache cannot cut the recording short.

Output doc/demo.gif

Set FontSize 18
Set Width 1200
Set Height 340
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 1ms

Hide
Type "dart run example/hf_tokenizers_example.dart"
Enter
Wait+Screen@300s /\[2 tok\]/
Show
Sleep 2500ms
