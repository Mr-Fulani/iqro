/// «255» in Arabic-Indic digits, «٢٥٥», as the Mushaf numbers its ayahs.
String arabicIndicDigits(int number) => number
    .toString()
    .split('')
    .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
    .join();

/// A number beside words of the interface: Arabic-Indic digits for a reader
/// of Arabic, «255» for everyone else.
String readerDigits(String languageCode, int number) =>
    languageCode == 'ar' ? arabicIndicDigits(number) : '$number';
