class SelectedAllergens {
  final List<String> items;

  SelectedAllergens(List<String> src) : items = List.from(src);

  bool get isEmpty => items.isEmpty;

  void add(String s) {
    if (s.trim().isNotEmpty) {
      items.add(s.trim());
    }
  }

  String toDisplayString() {
    return items.join(', ');
  }

  Set<String> findMatchesInText(String text) {
    Set<String> matches = {};
    if (text.isEmpty) return matches;
    
    String lower = text.toLowerCase();
    for (String a in items) {
      String key = a.toLowerCase();
      if (lower.contains(key)) {
        matches.add(a);
      }
    }
    return matches;
  }
}
