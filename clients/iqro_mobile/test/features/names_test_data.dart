import 'dart:convert';
import 'dart:io';

import 'package:iqro_mobile/features/names/names_models.dart';

/// The contract example shared with the backend and the site.
Map<String, Object?> namesFixture() =>
    jsonDecode(
          File(
            '../../docs/names-of-allah/names-document.example.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

NamesDocument namesDocument() => NamesDocument.fromJson(namesFixture());
