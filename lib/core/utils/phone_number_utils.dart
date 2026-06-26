String normalizeNumber(String n) {
  if (n.isEmpty) return "";
  return n.replaceAll(RegExp(r'[^0-9+]'), '');
}

String standardizePhoneNumberForWhatsApp(String phoneNumber) {
  if (phoneNumber.isEmpty) {
    return "";
  }

  // Remove all non-digit characters except + sign
  String cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), "");

  if (cleaned.startsWith("+60")) {
    return cleaned.substring(1);
  } else if (cleaned.startsWith("+")) {
    return cleaned.substring(1);
  } else if (cleaned.startsWith("60")) {
    return cleaned;
  } else if (cleaned.startsWith("0")) {
    return "60${cleaned.substring(1)}";
  } else if (cleaned.length >= 9 && cleaned.length <= 10) {
    return "60$cleaned";
  } else {
    return cleaned;
  }
}
