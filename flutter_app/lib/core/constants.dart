import 'package:flutter_dotenv/flutter_dotenv.dart';

String get kBackendUrl => dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000';
String get kWsUrl => dotenv.env['WS_URL'] ?? 'ws://10.0.2.2:8000/ws/match';
const int kCallDurationSeconds = 180;
