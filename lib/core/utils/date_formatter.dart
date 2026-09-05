import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _timeFormat = DateFormat('h:mm a');
  static final DateFormat _dayFormat = DateFormat('EEEE');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yy');

  /// Formats a timestamp for the chat list (e.g., "10:42 PM", "Yesterday", "Monday", "05/09/26")
  static String formatChatListTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final difference = today.difference(messageDate).inDays;

    if (difference == 0) {
      return _timeFormat.format(dateTime);
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return _dayFormat.format(dateTime);
    } else {
      return _dateFormat.format(dateTime);
    }
  }

  /// Formats a timestamp for inside a chat bubble (e.g., "10:42 PM")
  static String formatBubbleTime(DateTime dateTime) {
    return _timeFormat.format(dateTime);
  }
}
