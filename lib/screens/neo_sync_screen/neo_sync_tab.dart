import 'package:flutter/material.dart';
import 'login_screen/neo_sync_content.dart';

class NeoSyncTab extends StatefulWidget {
  const NeoSyncTab({super.key});

  @override
  State<NeoSyncTab> createState() => _NeoSyncTabState();
}

class _NeoSyncTabState extends State<NeoSyncTab> {
  @override
  Widget build(BuildContext context) {
    return const NeoSyncContent();
  }
}
