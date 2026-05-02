import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/powersync_schema.dart';

class SupabasePowerSyncConnector extends PowerSyncBackendConnector {
  static const _powerSyncUrl = 'https://sync.kratosgym.ro';

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    return PowerSyncCredentials(
      endpoint: _powerSyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    // This first migration keeps writes on Supabase. Do not mark local writes
    // complete until each write path has an explicit upload implementation.
    throw UnimplementedError('PowerSync writes are not migrated yet.');
  }
}

class PowerSyncService {
  static late final PowerSyncDatabase db;
  static bool _isOpen = false;
  static bool _isConnected = false;

  static Future<void> initialize() async {
    if (_isOpen) return;

    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'kratos-powersync.db');

    db = PowerSyncDatabase(schema: powersyncSchema, path: path);
    await db.initialize();
    _isOpen = true;
  }

  static Future<void> connectIfAuthenticated() async {
    await initialize();
    if (_isConnected || Supabase.instance.client.auth.currentUser == null) {
      return;
    }

    await db.connect(connector: SupabasePowerSyncConnector());
    _isConnected = true;
  }

  static Future<void> disconnect() async {
    if (!_isOpen || !_isConnected) return;

    await db.disconnect();
    _isConnected = false;
  }

  static bool get isInitialized => _isOpen;
}
