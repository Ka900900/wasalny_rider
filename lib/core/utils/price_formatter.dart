/// أدوات مساعدة لعرض الأسعار بالجنيه المصري (ج.م) في تطبيق الرايدر.
///
/// كل الأسعار تُجلب من الـ Backend فقط، ويأتي أغلبها كقيم نصية مثل
/// `"349.12"` (حقل `price` في كائن الرحلة) أو رقمية مثل `finalPrice`
/// في استجابة `/rides/fare`. هذه الدوال توحّد القراءة والتنسيق.
library;

/// يحوّل قيمة سعر من الـ Backend إلى `double`.
///
/// الـ Backend يعيد السعر أحياناً رقماً (`349.12`) وأحياناً نصاً
/// (`"349.12"`)، وأحياناً `null`. ترجع `0` عندما لا تكون القيمة صالحة.
double parsePrice(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    return double.tryParse(trimmed) ?? 0;
  }
  return 0;
}

/// ينسّق السعر بالجنيه المصري مع فواصل الآلاف، مثال:
/// `349.12` ← `"349.12 ج.م"`، و`1200` ← `"1,200 ج.م"`.
///
/// الأعداد الصحيحة تُعرض بدون كسور، والأعداد الكسرية تُقرّب لخانتين.
String formatEGP(num? value) {
  final v = value ?? 0;
  final rounded = v.roundToDouble();
  final hasDecimals = (v - rounded).abs() > 0.004;
  final text = hasDecimals ? v.toStringAsFixed(2) : rounded.toStringAsFixed(0);

  // إضافة فاصل الآلاف (`,`) يدوياً — بدون الاعتماد على حزمة `intl`.
  final parts = text.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final body = parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
  return '$body ج.م';
}
