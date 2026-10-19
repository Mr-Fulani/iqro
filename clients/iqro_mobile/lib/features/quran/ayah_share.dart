import '../../core/share/content_share.dart';

/// An ayah as shared: the surah and its number, the Arabic, the meaning
/// with its translator, and a link to the ayah on the site.
ContentShare ayahContentShare({
  required String locale,
  required String surahName,
  required int surah,
  required int ayah,
  required String arabic,
  required String readInIqro,
  String translation = '',
  String translator = '',
}) => ContentShare(
  title: '$surahName · $surah:$ayah',
  arabic: arabic,
  translation: translation,
  reference: translation.trim().isEmpty ? '' : translator.trim(),
  url: ayahShareUrl(locale, surah, ayah),
  readInIqro: readInIqro,
);
