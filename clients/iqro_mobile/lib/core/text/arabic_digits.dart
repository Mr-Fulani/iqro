/// «255» in Arabic-Indic digits, «٢٥٥», as the Mushaf numbers its ayahs.
String arabicIndicDigits(int number) => number
    .toString()
    .split('')
    .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
    .join();
