

extension StringExt on String {
  static final firstLetterPattern = RegExp("(^|[^\\w])(\\w)");

  String capitalize() {
    if (isEmpty) {
      return this;
    }

    return replaceAllMapped(firstLetterPattern, (match) =>'${match.group(1)}${match.group(2).toUpperCase()}');
  }
}
