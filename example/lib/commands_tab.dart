import 'package:flutter/material.dart';
import 'package:saic_ismart/saic_ismart.dart';

class CommandsTab extends StatefulWidget {
  final SaicClient client;
  final Vehicle vehicle;

  const CommandsTab({
    super.key,
    required this.client,
    required this.vehicle,
  });

  @override
  State<CommandsTab> createState() => _CommandsTabState();
}

class _CommandsTabState extends State<CommandsTab> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓ Command sent successfully'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on SaicException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showClimateSheet() async {
    final result = await showModalBottomSheet<_ClimateParams>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ClimateSheet(),
    );
    if (result == null || !mounted) return;
    await _run(() => widget.client.startClimate(
          widget.vehicle.vin,
          temperatureIndex: result.temperatureIndex,
          mode: result.mode,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final vin = widget.vehicle.vin;

    return Scaffold(
      appBar: AppBar(title: const Text('Commands')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CommandCard(
            icon: Icons.lock_rounded,
            label: 'Lock',
            description: 'Lock all doors',
            busy: _busy,
            onTap: () => _run(() => widget.client.lockVehicle(vin)),
          ),
          _CommandCard(
            icon: Icons.lock_open_rounded,
            label: 'Unlock',
            description: 'Unlock all doors',
            busy: _busy,
            onTap: () => _run(() => widget.client.unlockVehicle(vin)),
          ),
          _CommandCard(
            icon: Icons.my_location_rounded,
            label: 'Find My Car',
            description: 'Sound horn and flash lights',
            busy: _busy,
            onTap: () => _run(() => widget.client.findMyCar(vin)),
          ),
          _CommandCard(
            icon: Icons.ac_unit_rounded,
            label: 'Start Climate',
            description: 'Configure and start A/C or heating',
            busy: _busy,
            onTap: _showClimateSheet,
          ),
          _CommandCard(
            icon: Icons.stop_circle_outlined,
            label: 'Stop Climate',
            description: 'Stop climate control',
            busy: _busy,
            onTap: () => _run(() => widget.client.stopClimate(vin)),
          ),
        ],
      ),
    );
  }
}

// ── Command card ──────────────────────────────────────────────────────────────

class _CommandCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool busy;
  final VoidCallback onTap;

  const _CommandCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: busy ? Colors.grey.shade400 : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: busy ? Colors.grey.shade400 : null,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Climate bottom sheet ──────────────────────────────────────────────────────

class _ClimateParams {
  final ClimateMode mode;
  final int temperatureIndex;

  const _ClimateParams({required this.mode, required this.temperatureIndex});
}

class _ClimateSheet extends StatefulWidget {
  const _ClimateSheet();

  @override
  State<_ClimateSheet> createState() => _ClimateSheetState();
}

class _ClimateSheetState extends State<_ClimateSheet> {
  ClimateMode _mode = ClimateMode.normal;
  double _tempIndex = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Start Climate',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Mode', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          RadioGroup<ClimateMode>(
            groupValue: _mode,
            onChanged: (v) {
              if (v != null) setState(() => _mode = v);
            },
            child: Column(
              children: ClimateMode.values
                  .where((m) => m != ClimateMode.off)
                  .map((m) => RadioListTile<ClimateMode>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_modeLabel(m)),
                        value: m,
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Temperature index', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Index ${_tempIndex.round()} — exact temperature undocumented',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
            ),
          ),
          Slider(
            min: 0,
            max: 15,
            divisions: 15,
            value: _tempIndex,
            label: _tempIndex.round().toString(),
            onChanged: (v) => setState(() => _tempIndex = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(
              _ClimateParams(
                mode: _mode,
                temperatureIndex: _tempIndex.round(),
              ),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(ClimateMode mode) => switch (mode) {
        ClimateMode.blow => 'Blow — fan only',
        ClimateMode.normal => 'Normal — A/C or heating',
        ClimateMode.defrost => 'Defrost — windscreen + max fan',
        ClimateMode.off => 'Off',
      };
}
