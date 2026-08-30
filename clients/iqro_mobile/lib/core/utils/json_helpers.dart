Map<String, Object?> jsonMap(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Expected a JSON object');
}

List<Object?> jsonResults(Object? value) {
  if (value is List) return List<Object?>.from(value);
  if (value is Map) {
    final results = value['results'];
    if (results is List) return List<Object?>.from(results);
    for (final key in <String>['items', 'data', 'methods', 'reminders']) {
      final nested = value[key];
      if (nested is List) return List<Object?>.from(nested);
    }
  }
  return const <Object?>[];
}

String? localizedField(Map<String, Object?> json, String locale, String name) {
  return json['${name}_$locale']?.toString() ??
      json['${name}_en']?.toString() ??
      json['${name}_ru']?.toString() ??
      json['${name}_ar']?.toString();
}
