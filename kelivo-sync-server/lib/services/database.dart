import 'dart:io';

import 'package:postgres/postgres.dart';

class Database {
  static late Pool pool;

  static Future<void> init() async {
    final databaseUrl =
        Platform.environment['DATABASE_URL'] ??
        'postgresql://kelivo:kelivo_dev@localhost:5432/kelivo_sync';

    final endpoint = Endpoint(
      host: _parseHost(databaseUrl),
      port: _parsePort(databaseUrl),
      database: _parseDatabase(databaseUrl),
      username: _parseUsername(databaseUrl),
      password: _parsePassword(databaseUrl),
    );

    pool = Pool.withEndpoints([
      endpoint,
    ], settings: PoolSettings(maxConnectionCount: 10));
  }

  static Future<void> createTables() async {
    await pool.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        encrypted_dek TEXT,
        dek_nonce TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // Add DEK columns if they don't exist (migration for existing databases).
    await pool.execute('''
      ALTER TABLE users ADD COLUMN IF NOT EXISTS encrypted_dek TEXT
    ''');
    await pool.execute('''
      ALTER TABLE users ADD COLUMN IF NOT EXISTS dek_nonce TEXT
    ''');

    await pool.execute('''
      CREATE TABLE IF NOT EXISTS refresh_tokens (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token TEXT UNIQUE NOT NULL,
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await pool.execute('''
      CREATE TABLE IF NOT EXISTS change_entries (
        id BIGSERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        category TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}',
        updated_at BIGINT NOT NULL,
        deleted_at BIGINT,
        server_seq BIGSERIAL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, category, record_id)
      )
    ''');

    await pool.execute('''
      CREATE INDEX IF NOT EXISTS idx_change_entries_user_seq
        ON change_entries(user_id, server_seq)
    ''');

    await pool.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        sha256_hash TEXT NOT NULL,
        original_path TEXT NOT NULL DEFAULT '',
        content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
        size BIGINT NOT NULL DEFAULT 0,
        stored_path TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, sha256_hash)
      )
    ''');

    await pool.execute('''
      CREATE TABLE IF NOT EXISTS generation_tasks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        conversation_id TEXT NOT NULL,
        provider_sync_id TEXT NOT NULL,
        messages JSONB NOT NULL DEFAULT '[]',
        parameters JSONB NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'pending',
        result_chunks JSONB NOT NULL DEFAULT '[]',
        final_content TEXT,
        error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await pool.execute('''
      CREATE INDEX IF NOT EXISTS idx_gen_tasks_user_status
        ON generation_tasks(user_id, status)
    ''');

    await pool.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        platform TEXT NOT NULL,
        push_token TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(user_id, push_token)
      )
    ''');
  }

  static String _parseHost(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.host;
  }

  static int _parsePort(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.port > 0 ? uri.port : 5432;
  }

  static String _parseDatabase(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'kelivo_sync';
  }

  static String _parseUsername(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.userInfo.split(':').first;
  }

  static String _parsePassword(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    final parts = uri.userInfo.split(':');
    return parts.length > 1 ? parts.sublist(1).join(':') : '';
  }
}
