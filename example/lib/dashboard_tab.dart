import 'package:flutter/material.dart';
import 'package:saic_ismart/saic_ismart.dart';

class DashboardTab extends StatefulWidget {
  final SaicClient client;
  final Vehicle vehicle;

  const DashboardTab({
    super.key,
    required this.client,
    required this.vehicle,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  VehicleStatus? _status;
  String? _error;
  DateTime? _lastUpdated;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (forceRefresh) {
        widget.client.clearCacheFor(widget.vehicle.vin);
      }
      final status = await widget.client.getVehicleStatus(widget.vehicle.vin);
      if (!mounted) return;
      setState(() {
        _status = status;
        _lastUpdated = DateTime.now();
      });
    } on SaicException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final displayName = vehicle.vehicleName ??
        [vehicle.brandName, vehicle.modelName]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayName.isEmpty ? 'Vehicle' : displayName),
            Text(
              _vinDisplay(vehicle.vin),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
            ),
          ],
        ),
        actions: [
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _timeAgo(_lastUpdated!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchStatus(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error != null) return _buildError();
    if (_status == null) return _buildEmpty();
    return _buildCards(_status!);
  }

  Widget _buildCards(VehicleStatus status) {
    final basic = status.basicVehicleStatus;
    final gps = status.gpsPosition;

    final lockLabel = basic?.lockState?.name ?? 'Unknown';
    final fuel = basic?.fuelLevelPrc;
    final mileage = basic?.mileageKm;
    final interiorTemp = basic?.interiorTemperatureCelsius;
    final batteryV = basic?.batteryVoltageVolts;
    final lat = gps?.latitudeDegrees;
    final lon = gps?.longitudeDegrees;
    final flp = basic?.frontLeftTyrePressureBar;
    final frp = basic?.frontRightTyrePressureBar;
    final rlp = basic?.rearLeftTyrePressureBar;
    final rrp = basic?.rearRightTyrePressureBar;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusCard(
          icon: Icons.lock_rounded,
          label: 'Lock',
          value: lockLabel[0].toUpperCase() + lockLabel.substring(1),
          color: basic?.lockState == LockStatus.locked
              ? Colors.green
              : Colors.orange,
        ),
        _StatusCard(
          icon: Icons.local_gas_station_rounded,
          label: 'Fuel level',
          value: fuel != null ? '$fuel%' : 'N/A',
        ),
        _StatusCard(
          icon: Icons.route_rounded,
          label: 'Mileage',
          value: mileage != null ? '${mileage.toStringAsFixed(1)} km' : 'N/A',
        ),
        _StatusCard(
          icon: Icons.thermostat_rounded,
          label: 'Interior temperature',
          value: interiorTemp != null ? '$interiorTemp °C' : 'N/A',
        ),
        _StatusCard(
          icon: Icons.my_location_rounded,
          label: 'Location',
          value: (lat != null && lon != null)
              ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}'
              : 'N/A',
        ),
        _StatusCard(
          icon: Icons.battery_charging_full_rounded,
          label: 'Battery voltage',
          value: batteryV != null ? '${batteryV.toStringAsFixed(1)} V' : 'N/A',
        ),
        _TyrePressureCard(fl: flp, fr: frp, rl: rlp, rr: rrp),
      ],
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        7,
        (_) => const _SkeletonCard(),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
        const SizedBox(height: 16),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.tonal(
            onPressed: () => _fetchStatus(forceRefresh: true),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No status data available.'));
  }

  static String _vinDisplay(String vin) {
    if (vin.length <= 10) return vin;
    return '${vin.substring(0, 6)}…${vin.substring(vin.length - 4)}';
  }

  static String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} h ago';
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tyre pressure card ────────────────────────────────────────────────────────

class _TyrePressureCard extends StatelessWidget {
  final double? fl;
  final double? fr;
  final double? rl;
  final double? rr;

  const _TyrePressureCard({this.fl, this.fr, this.rl, this.rr});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String fmt(double? v) => v != null ? '${v.toStringAsFixed(2)} bar' : 'N/A';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tire_repair_rounded,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text('Tyre pressures', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _TyreCell(label: 'FL', value: fmt(fl)),
                _TyreCell(label: 'FR', value: fmt(fr)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _TyreCell(label: 'RL', value: fmt(rl)),
                _TyreCell(label: 'RR', value: fmt(rr)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TyreCell extends StatelessWidget {
  final String label;
  final String value;

  const _TyreCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        children: [
          Text(
            '$label  ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
            ),
          ),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _Shimmer(width: 22, height: 22, radius: 4),
            const SizedBox(width: 12),
            _Shimmer(width: 100, height: 14, radius: 6),
            const Spacer(),
            _Shimmer(width: 60, height: 14, radius: 6),
          ],
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
