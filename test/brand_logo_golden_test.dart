import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dialysis_care/main.dart';
import 'package:dialysis_care/theme.dart';

Future<void> _register(String family, String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  await (FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer))))
      .load();
}

/// Register real fonts so golden captures render readable text and Material
/// icons instead of the default test placeholder boxes.
Future<void> _loadFonts() async {
  const arial = '/System/Library/Fonts/Supplemental/Arial.ttf';
  for (final family in const [
    'Euclid Circular A',
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ]) {
    await _register(family, arial);
  }
  final home = Platform.environment['HOME'];
  await _register(
    'MaterialIcons',
    '$home/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

/// Decode any asset images currently mounted so they paint in the next frame.
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('app bar + drawer brand lockup goldens', (tester) async {
    // The app nests ListTiles inside a bordered DecoratedBox; the resulting
    // "ink may be invisible" diagnostic is benign — keep it out of the run.
    // (Set inside the test body so it survives the harness's own handler.)
    final harnessOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('ink splashes may be invisible')) {
        return;
      }
      harnessOnError?.call(details);
    };

    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrandTheme(),
        home: const ChatScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );

    // The disclaimer dialog is shown from a post-frame callback; accept it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pump();
    // Let the dialog dismiss and the (mocked, 400) session init resolve.
    await tester.pump(const Duration(milliseconds: 600));
    await _settleImages(tester);

    await expectLater(
      find.byType(AppBar),
      matchesGoldenFile('goldens/app_bar.png'),
    );

    // Open the navigation drawer and let it slide fully in.
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settleImages(tester);

    await expectLater(
      find.byType(Drawer),
      matchesGoldenFile('goldens/drawer.png'),
    );
  });
}
