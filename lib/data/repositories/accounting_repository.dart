import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/account_transaction.dart';

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  return AccountingRepository();
});

class AccountingFilter {
  final String type;
  final DateTime? startDate;
  final DateTime? endDate;

  const AccountingFilter({this.type = 'all', this.startDate, this.endDate});
}

class AccountingSummary {
  final double income;
  final double expense;

  const AccountingSummary({required this.income, required this.expense});

  double get net => income - expense;
}

class AccountingRepository {
  static const _databaseName = 'accounting.db';
  static const _databaseVersion = 1;
  static const tableName = 'account_transactions';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            currency TEXT NOT NULL,
            category TEXT NOT NULL,
            merchant TEXT NOT NULL,
            transaction_date TEXT NOT NULL,
            note TEXT NOT NULL,
            source_image_path TEXT,
            raw_llm_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
  }

  Future<int> insert(AccountTransaction transaction) async {
    final db = await database;
    return db.insert(tableName, transaction.toMap()..remove('id'));
  }

  Future<int> update(AccountTransaction transaction) async {
    final id = transaction.id;
    if (id == null) {
      throw ArgumentError('Cannot update a transaction without an id.');
    }

    final db = await database;
    return db.update(
      tableName,
      transaction.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    return db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<AccountTransaction>> list({
    AccountingFilter filter = const AccountingFilter(),
    int limit = 200,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <Object?>[];
    _applyFilter(filter, where, whereArgs);

    final rows = await db.query(
      tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'transaction_date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(AccountTransaction.fromMap).toList();
  }

  Future<List<AccountTransaction>> listRecent({int limit = 50}) {
    return list(limit: limit);
  }

  Future<AccountingSummary> summary({
    AccountingFilter filter = const AccountingFilter(),
  }) async {
    final transactions = await list(filter: filter, limit: 10000);
    double income = 0;
    double expense = 0;

    for (final transaction in transactions) {
      if (transaction.type == 'income') {
        income += transaction.amount;
      } else {
        expense += transaction.amount;
      }
    }

    return AccountingSummary(income: income, expense: expense);
  }

  void _applyFilter(
    AccountingFilter filter,
    List<String> where,
    List<Object?> whereArgs,
  ) {
    if (filter.type == 'income' || filter.type == 'expense') {
      where.add('type = ?');
      whereArgs.add(filter.type);
    }
    if (filter.startDate != null) {
      where.add('transaction_date >= ?');
      whereArgs.add(filter.startDate!.toIso8601String());
    }
    if (filter.endDate != null) {
      where.add('transaction_date < ?');
      whereArgs.add(filter.endDate!.toIso8601String());
    }
  }
}
