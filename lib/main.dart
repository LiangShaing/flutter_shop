import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'menu_page.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isSupabaseConfigured = _supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty;
  if (isSupabaseConfigured) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabasePublishableKey);
  }

  runApp(FlutterShopApp(isSupabaseConfigured: isSupabaseConfigured));
}

class FlutterShopApp extends StatelessWidget {
  const FlutterShopApp({super.key, required this.isSupabaseConfigured});

  final bool isSupabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '門市訂單',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B58), surface: const Color(0xFFF7F8F6)),
      ),
      home: MenuPage(client: isSupabaseConfigured ? Supabase.instance.client : null),
    );
  }
}

class SupabaseSetupPage extends StatelessWidget {
  const SupabaseSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('門市訂單')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, size: 36, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('尚未設定 Supabase', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('啟動 App 時提供專案 URL 與 publishable key：'),
                const SizedBox(height: 12),
                const SelectableText(
                  'flutter run '
                  '--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                  '--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY',
                ),
                const SizedBox(height: 8),
                Text('不要將 service_role key 放入 App。', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
