import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_platform_stub.dart'
    if (dart.library.io) 'mqtt_platform_io.dart'
    if (dart.library.js_interop) 'mqtt_platform_web.dart'
    if (dart.library.html) 'mqtt_platform_web.dart';

abstract class MqttPlatformHelper {
  static MqttClient createClient(String broker, String clientId) {
    return createPlatformClient(broker, clientId);
  }
}
