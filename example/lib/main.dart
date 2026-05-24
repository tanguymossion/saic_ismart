import 'package:flutter/material.dart';
import 'package:saic_ismart/saic_ismart.dart';

import 'dashboard_tab.dart';
import 'commands_tab.dart';

void main() {
  runApp(const SaicApp());
}

class SaicApp extends StatelessWidget {
  const SaicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iSmart',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0057B8)),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFFE8E8E8)),
          ),
          color: Colors.white,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ── Login ─────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Pre-fill from --dart-define=SAIC_USERNAME=... --dart-define=SAIC_PASSWORD=...
  static const _envUsername = String.fromEnvironment('SAIC_USERNAME');
  static const _envPassword = String.fromEnvironment('SAIC_PASSWORD');

  late final TextEditingController _usernameCtrl =
      TextEditingController(text: _envUsername);
  late final TextEditingController _passwordCtrl =
      TextEditingController(text: _envPassword);

  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _showError('Username and password are required.');
      return;
    }
    setState(() => _loading = true);
    try {
      final client = SaicClient(
        SaicConfig(username: username, password: password),
      );
      await client.login();
      final vehicles = await client.getVehicles();
      if (!mounted) return;
      if (vehicles.isEmpty) {
        _showError('No vehicles found on this account.');
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              HomeScreen(client: client, vehicle: vehicles.first),
        ),
      );
    } on SaicException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.directions_car_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'iSmart',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'SAIC Connected Vehicle',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _usernameCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  enabled: !_loading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  enabled: !_loading,
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _connect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Home (tab host) ───────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final SaicClient client;
  final Vehicle vehicle;

  const HomeScreen({
    super.key,
    required this.client,
    required this.vehicle,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardTab(client: widget.client, vehicle: widget.vehicle),
          CommandsTab(client: widget.client, vehicle: widget.vehicle),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_remote_outlined),
            selectedIcon: Icon(Icons.settings_remote_rounded),
            label: 'Commands',
          ),
        ],
      ),
    );
  }
}
