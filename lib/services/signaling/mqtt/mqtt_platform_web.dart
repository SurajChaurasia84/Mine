import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformClient(String broker, String clientId) {
  final cleanBroker = broker.replaceAll('ws://', '').replaceAll('wss://', '').split('/').first;
  final wsUrl = 'ws://$cleanBroker:8000/mqtt';
  final client = MqttBrowserClient(wsUrl, clientId);
  client.port = 8000;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
