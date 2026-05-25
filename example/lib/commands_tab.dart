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
  bool _rearWindowHeatOn = false;

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

  Future<void> _showHeatedSeatsSheet() async {
    final result = await showModalBottomSheet<_HeatedSeatsParams>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _HeatedSeatsSheet(),
    );
    if (result == null || !mounted) return;
    await _run(() => widget.client.controlHeatedSeats(
          widget.vehicle.vin,
          driverLevel: result.driverLevel,
          passengerLevel: result.passengerLevel,
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
          // ── Locks ──────────────────────────────────────────────────────────
          _PairedCommandCard(
            leftIcon: Icons.lock_rounded,
            leftLabel: 'Lock',
            leftDescription: 'Lock all doors',
            rightIcon: Icons.lock_open_rounded,
            rightLabel: 'Unlock',
            rightDescription: 'Unlock all doors',
            busy: _busy,
            onLeftTap: () => _run(() => widget.client.lockVehicle(vin)),
            onRightTap: () => _run(() => widget.client.unlockVehicle(vin)),
          ),
          _CommandCard(
            icon: Icons.airport_shuttle,
            label: 'Open Tailgate',
            description: 'Open the boot remotely',
            busy: _busy,
            onTap: () => _run(() => widget.client.openTailgate(vin)),
          ),
          // ── Find My Car ────────────────────────────────────────────────────
          _PairedCommandCard(
            leftIcon: Icons.my_location_rounded,
            leftLabel: 'Find My Car',
            leftDescription: 'Sound horn and flash lights',
            rightIcon: Icons.location_off,
            rightLabel: 'Stop Find My Car',
            rightDescription: 'Silence horn and lights',
            busy: _busy,
            onLeftTap: () => _run(() => widget.client.findMyCar(vin)),
            onRightTap: () => _run(() => widget.client.stopFindMyCar(vin)),
          ),
          // ── Climate ────────────────────────────────────────────────────────
          _PairedCommandCard(
            leftIcon: Icons.ac_unit_rounded,
            leftLabel: 'Start Climate',
            leftDescription: 'Configure and start A/C or heating',
            leftConfigure: true,
            rightIcon: Icons.stop_circle_outlined,
            rightLabel: 'Stop Climate',
            rightDescription: 'Stop climate control',
            busy: _busy,
            onLeftTap: _showClimateSheet,
            onRightTap: () => _run(() => widget.client.stopClimate(vin)),
          ),
          _PairedCommandCard(
            leftIcon: Icons.air,
            leftLabel: 'Start Blowing',
            leftDescription: 'Fan only — no heating or cooling',
            rightIcon: Icons.ac_unit,
            rightLabel: 'Start Defrost',
            rightDescription: 'Max fan to clear windscreen',
            busy: _busy,
            onLeftTap: () => _run(() => widget.client.startBlowing(vin)),
            onRightTap: () => _run(() => widget.client.startDefrost(vin)),
          ),
          _CommandCard(
            icon: Icons.airline_seat_recline_extra_rounded,
            label: 'Heated Seats',
            description: 'Set driver and passenger heat levels',
            busy: _busy,
            onTap: _showHeatedSeatsSheet,
            configure: true,
          ),
          _ToggleCommandCard(
            icon: Icons.deblur,
            label: 'Rear Window Heat',
            description: 'Heat the rear windscreen',
            busy: _busy,
            value: _rearWindowHeatOn,
            onChanged: (v) async {
              setState(() => _rearWindowHeatOn = v);
              await _run(
                  () => widget.client.controlRearWindowHeat(vin, enable: v));
            },
          ),
          // ── Sunroof ────────────────────────────────────────────────────────
          _PairedCommandCard(
            leftIcon: Icons.wb_sunny,
            leftLabel: 'Open Sunroof',
            leftDescription: 'Open the sunroof',
            rightIcon: Icons.wb_cloudy,
            rightLabel: 'Close Sunroof',
            rightDescription: 'Close the sunroof',
            busy: _busy,
            onLeftTap: () => _run(() => widget.client.controlSunroof(vin)),
            onRightTap: () =>
                _run(() => widget.client.controlSunroof(vin, open: false)),
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
  final bool configure;

  const _CommandCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.busy,
    required this.onTap,
    this.configure = false,
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
                    if (configure)
                      Text(
                        'Tap to configure',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary.withValues(
                            alpha: busy ? 0.3 : 0.7,
                          ),
                          fontStyle: FontStyle.italic,
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
                  configure
                      ? Icons.tune
                      : Icons.chevron_right_rounded,
                  color: configure
                      ? theme.colorScheme.primary.withValues(alpha: 0.6)
                      : Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Paired command card ───────────────────────────────────────────────────────

class _PairedCommandCard extends StatelessWidget {
  final IconData leftIcon;
  final String leftLabel;
  final String leftDescription;
  final VoidCallback onLeftTap;
  final bool leftConfigure;
  final IconData rightIcon;
  final String rightLabel;
  final String rightDescription;
  final VoidCallback onRightTap;
  final bool busy;

  const _PairedCommandCard({
    required this.leftIcon,
    required this.leftLabel,
    required this.leftDescription,
    required this.onLeftTap,
    this.leftConfigure = false,
    required this.rightIcon,
    required this.rightLabel,
    required this.rightDescription,
    required this.onRightTap,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _HalfCard(
                icon: leftIcon,
                label: leftLabel,
                description: leftDescription,
                busy: busy,
                onTap: onLeftTap,
                configure: leftConfigure,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HalfCard(
                icon: rightIcon,
                label: rightLabel,
                description: rightDescription,
                busy: busy,
                onTap: onRightTap,
                configure: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalfCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool busy;
  final VoidCallback onTap;
  final bool configure;

  const _HalfCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.busy,
    required this.onTap,
    this.configure = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color:
                        busy ? Colors.grey.shade400 : theme.colorScheme.primary,
                  ),
                  const Spacer(),
                  Icon(
                    configure ? Icons.tune : Icons.chevron_right_rounded,
                    size: 16,
                    color: configure
                        ? theme.colorScheme.primary
                            .withValues(alpha: busy ? 0.3 : 0.6)
                        : Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              if (configure)
                Text(
                  'Tap to configure',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary
                        .withValues(alpha: busy ? 0.3 : 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toggle command card ───────────────────────────────────────────────────────

class _ToggleCommandCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool busy;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _ToggleCommandCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.busy,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            Switch(
              value: value,
              onChanged: busy ? null : onChanged,
            ),
          ],
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

// ── Heated seats bottom sheet ─────────────────────────────────────────────────

class _HeatedSeatsParams {
  final HeatLevel driverLevel;
  final HeatLevel passengerLevel;

  const _HeatedSeatsParams({
    required this.driverLevel,
    required this.passengerLevel,
  });
}

class _HeatedSeatsSheet extends StatefulWidget {
  const _HeatedSeatsSheet();

  @override
  State<_HeatedSeatsSheet> createState() => _HeatedSeatsSheetState();
}

class _HeatedSeatsSheetState extends State<_HeatedSeatsSheet> {
  HeatLevel _driver = HeatLevel.off;
  HeatLevel _passenger = HeatLevel.off;

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
              Text('Heated Seats',
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
          _HeatLevelRow(
            label: 'Driver seat',
            value: _driver,
            onChanged: (v) => setState(() => _driver = v),
          ),
          const SizedBox(height: 16),
          _HeatLevelRow(
            label: 'Passenger seat',
            value: _passenger,
            onChanged: (v) => setState(() => _passenger = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(
              _HeatedSeatsParams(
                driverLevel: _driver,
                passengerLevel: _passenger,
              ),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class _HeatLevelRow extends StatelessWidget {
  final String label;
  final HeatLevel value;
  final ValueChanged<HeatLevel> onChanged;

  const _HeatLevelRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        DropdownButton<HeatLevel>(
          value: value,
          underline: const SizedBox.shrink(),
          items: HeatLevel.values
              .map((l) => DropdownMenuItem(
                    value: l,
                    child: Text(_heatLevelLabel(l)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  static String _heatLevelLabel(HeatLevel level) => switch (level) {
        HeatLevel.off => 'Off',
        HeatLevel.low => 'Low',
        HeatLevel.medium => 'Medium',
        HeatLevel.high => 'High',
      };
}
