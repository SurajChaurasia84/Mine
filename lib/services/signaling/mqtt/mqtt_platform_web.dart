import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformClient(String broker, String clientId) {
  final cleanBroker = broker
      .replaceAll('ws://', '')
      .replaceAll('wss://', '')
      .split('/')
      .first
      .split(':')
      .first;

  String wsUrl;
  int port;
  if (cleanBroker.contains('emqx.io')) {
    wsUrl = 'wss://$cleanBroker:8084/mqtt';
    port = 8084;
  } else if (cleanBroker.contains('hivemq.com')) {
    wsUrl = 'ws://$cleanBroker:8000/mqtt';
    port = 8000;
  } else {
    wsUrl = 'wss://$cleanBroker/mqtt';
    port = 8084;
  }

  final client = MqttBrowserClient.withPort(wsUrl, clientId, port);
  client.websocketProtocols = ['mqtt', 'mqttv3.1', 'mqttv3.1.1'];
  return client;
}
