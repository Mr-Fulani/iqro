import 'audio_models.dart';

const _fallbackPortraits = <String, String>{
  'qf-1-abdulbaset-abdulsamad-mujawwad':
      '/reciters/abdul-baset-abdul-samad.webp',
  'qf-2-abdul-baset-abdul-samad': '/reciters/abdul-baset-abdul-samad.webp',
  'qf-3-abdur-rahman-as-sudais': '/reciters/abdur-rahman-as-sudais.webp',
  'qf-4-abu-bakr-al-shatri': '/reciters/abu-bakr-al-shatri.webp',
  'qf-5-hani-ar-rifai': '/reciters/hani-ar-rifai.webp',
  'qf-6-mahmoud-khaleel-al-husary': '/reciters/mahmoud-khaleel-al-husary.webp',
  'qf-7-mishari-rashid-al-afasy': '/reciters/mishari-rashid-al-afasy.webp',
  'qf-9-muhammad-siddiq-al-minshawi':
      '/reciters/muhammad-siddiq-al-minshawi.webp',
  'qf-10-saud-ash-shuraym': '/reciters/saud-ash-shuraym.webp',
  'qf-12-mahmoud-khaleel-al-husary': '/reciters/mahmoud-khaleel-al-husary.webp',
  'qf-13-saad-al-ghamdi': '/reciters/saad-al-ghamdi.webp',
  'qf-19-ahmed-ibn-ali-al-ajmy': '/reciters/ahmed-ibn-ali-al-ajmy.webp',
  'qf-158-abdullah-ali-jabir': '/reciters/abdullah-ali-jabir.webp',
  'qf-159-maher-al-muaiqly': '/reciters/maher-al-muaiqly.webp',
  'qf-160-bandar-baleela': '/reciters/bandar-baleela.webp',
  'qf-174-yasser-ad-dussary': '/reciters/yasser-ad-dussary.webp',
  'qf-175-abdullah-hamad-abu-sharida':
      '/reciters/abdullah-hamad-abu-sharida.webp',
  'qf-176-ahmed-tahoun': '/reciters/ahmed-tahoun.webp',
};

String? resolveReciterPortraitUrl(
  Reciter reciter, {
  required String apiBaseUrl,
}) {
  final managedUrl = reciter.portraitUrl?.trim();
  if (managedUrl != null && managedUrl.isNotEmpty) {
    final uri = Uri.tryParse(managedUrl);
    if (uri?.hasScheme == true) return managedUrl;
    return Uri.parse(apiBaseUrl).resolve(managedUrl).toString();
  }
  final fallbackPath = _fallbackPortraits[reciter.slug];
  return fallbackPath == null
      ? null
      : Uri.parse(apiBaseUrl).resolve(fallbackPath).toString();
}
