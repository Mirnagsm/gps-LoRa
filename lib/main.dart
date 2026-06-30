import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/supabase_config.dart';

void main() async {
  // Ensure Flutter bindings are initialized before calling async platform channels
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database
  await DatabaseService.instance.initDatabase();

  // Initialize Supabase if configured
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
      print('Supabase inicializado correctamente.');
    } catch (e) {
      print('Error al inicializar Supabase: $e');
    }
  } else {
    print('Supabase no está configurado, funcionando en modo offline local.');
  }

  runApp(const CampoMapApp());
}

class CampoMapApp extends StatelessWidget {
  const CampoMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampoMap Offline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          primary: Colors.green[800]!,
          secondary: Colors.brown[600]!,
          background: const Color(0xFFF9FBE7), // Organic background
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green[800],
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
