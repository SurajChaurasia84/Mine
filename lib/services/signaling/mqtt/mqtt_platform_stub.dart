import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformClient(String broker, String clientId) {
  throw UnsupportedError('Platform not supported');
}
