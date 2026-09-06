import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createPlatformClient(String broker, String clientId) {
  final client = MqttServerClient.withPort(broker, clientId, 1883);
  client.secure = false;
  return client;
}
