import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _dateFormat = DateFormat('MMM d, HH:mm:ss');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFresh();
  }

  Future<void> _loadFresh() async {
    await DatabaseService.reload();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recorded Locations')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final records = DatabaseService.getAllRecords();

    return Scaffold(
      appBar: AppBar(
        title: Text('Recorded Locations (${records.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _loadFresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: () async {
              await DatabaseService.clearAll();
              setState(() {});
            },
          ),
        ],
      ),
      body: records.isEmpty
          ? const Center(child: Text('No locations recorded yet.'))
          : ListView.separated(
        itemCount: records.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final r = records[index];
          return ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text('${r.latitude.toStringAsFixed(6)}, ${r.longitude.toStringAsFixed(6)}'),
            subtitle: Text(
              '${_dateFormat.format(r.timestamp)}  •  ±${r.accuracy.toStringAsFixed(1)}m',
            ),
          );
        },
      ),
    );
  }
}