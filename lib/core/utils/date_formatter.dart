import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _timeFormat12 = DateFormat('h:mm a');
  static final DateFormat _timeFormat24 = DateFormat('HH:mm');
  static final DateFormat _dayFormat = DateFormat('EEEE');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yy');

  /// Detects whether the device/system clock is configured for 24-hour format
  static bool is24HourFormat([BuildContext? context]) {
    if (context != null) {
      try {
        return MediaQuery.alwaysUse24HourFormatOf(context);
      } catch (_) {}
    }
    try {
      return PlatformDispatcher.instance.alwaysUse24HourFormat;
    } catch (_) {
      return false;
    }
  }

  /// Formats a timestamp for the chat list (e.g., "10:42 PM", "14:42", "Yesterday", "Monday", "05/09/26")
  static String formatChatListTime(DateTime? dateTime, [BuildContext? context]) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final difference = today.difference(messageDate).inDays;
    final is24 = is24HourFormat(context);
    final timeFormatter = is24 ? _timeFormat24 : _timeFormat12;

    if (difference == 0) {
      return timeFormatter.format(dateTime);
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return _dayFormat.format(dateTime);
    } else {
      return _dateFormat.format(dateTime);
    }
  }

  /// Formats a timestamp for inside a chat bubble (e.g., "10:42 PM" or "14:42")
  static String formatBubbleTime(DateTime dateTime, [BuildContext? context]) {
    final is24 = is24HourFormat(context);
    return is24 ? _timeFormat24.format(dateTime) : _timeFormat12.format(dateTime);
  }
}
