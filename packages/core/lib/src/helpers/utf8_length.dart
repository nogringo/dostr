/// How many bytes `utf8.encode` writes for [string], without encoding it.
int utf8Length(String string) {
  var length = 0;
  for (var i = 0; i < string.length; i++) {
    final unit = string.codeUnitAt(i);
    if (unit < 0x80) {
      length += 1;
    } else if (unit < 0x800) {
      length += 2;
    } else if ((unit & 0xFC00) == 0xD800 &&
        i + 1 < string.length &&
        (string.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
      length += 4;
      i++;
    } else {
      // a lone surrogate is written as U+FFFD, three bytes too
      length += 3;
    }
  }
  return length;
}
