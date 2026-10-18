import 'package:flutter/material.dart';

import 'ai/demo_services.dart';
import 'app.dart';
import 'data/demo_data.dart';

void main() {
  runApp(BhunteApp(store: demoStore(), assistant: DemoAssistantService(), scanner: DemoBarcodeScanner()));
}
