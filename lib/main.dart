import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:pico/bridge_generated.dart/frb_generated.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/landing_screen.dart';
import 'package:pico/screens/base_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS uses static linking, Android uses dynamic library
  if (Platform.isIOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await RustLib.init();
  }

  final dir = await getApplicationDocumentsDirectory();

  final db = await openDatabase(dbPath: dir.path);

  final clientFactory = await PicoClientFactory.tryLoad(db: db);

  if (clientFactory != null) {
    runApp(PicoApp(home: BaseScreen(clientFactory: clientFactory)));
  } else {
    runApp(PicoApp(home: LandingScreen(db: db)));
  }
}

class PicoApp extends StatelessWidget {
  final Widget home;

  const PicoApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: MaterialApp(
        title: 'Pico',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF36A18B)),
          useMaterial3: true,
          fontFamily: GoogleFonts.inter().fontFamily,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            titleTextStyle: mediumStyle,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF36A18B),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: GoogleFonts.inter().fontFamily,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            titleTextStyle: mediumStyle,
          ),
        ),
        themeMode: ThemeMode.dark,
        home: home,
      ),
    );
  }
}
