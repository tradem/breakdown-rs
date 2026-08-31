// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $SeasonCacheRowsTable extends SeasonCacheRows
    with TableInfo<$SeasonCacheRowsTable, SeasonCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    number,
    seriesId,
    title,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'season_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeasonCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $SeasonCacheRowsTable createAlias(String alias) {
    return $SeasonCacheRowsTable(attachedDatabase, alias);
  }
}

class SeasonCacheRow extends DataClass implements Insertable<SeasonCacheRow> {
  /// Mirrors `SeasonView.id`.
  final String id;

  /// Mirrors `SeasonView.number`.
  final int number;

  /// Mirrors `SeasonView.series_id` (opaque `SeriesId`).
  final String seriesId;

  /// Mirrors `SeasonView.title` (nullable).
  final String? title;

  /// Mirrors `SeasonView.updated_at` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `SeasonView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. Distinct from [updatedAt]; TTL is computed
  /// from this column only (D2).
  final DateTime cachedAt;
  const SeasonCacheRow({
    required this.id,
    required this.number,
    required this.seriesId,
    this.title,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['number'] = Variable<int>(number);
    map['series_id'] = Variable<String>(seriesId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  SeasonCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return SeasonCacheRowsCompanion(
      id: Value(id),
      number: Value(number),
      seriesId: Value(seriesId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory SeasonCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonCacheRow(
      id: serializer.fromJson<String>(json['id']),
      number: serializer.fromJson<int>(json['number']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      title: serializer.fromJson<String?>(json['title']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'number': serializer.toJson<int>(number),
      'seriesId': serializer.toJson<String>(seriesId),
      'title': serializer.toJson<String?>(title),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  SeasonCacheRow copyWith({
    String? id,
    int? number,
    String? seriesId,
    Value<String?> title = const Value.absent(),
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => SeasonCacheRow(
    id: id ?? this.id,
    number: number ?? this.number,
    seriesId: seriesId ?? this.seriesId,
    title: title.present ? title.value : this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  SeasonCacheRow copyWithCompanion(SeasonCacheRowsCompanion data) {
    return SeasonCacheRow(
      id: data.id.present ? data.id.value : this.id,
      number: data.number.present ? data.number.value : this.number,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      title: data.title.present ? data.title.value : this.title,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonCacheRow(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('seriesId: $seriesId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, number, seriesId, title, updatedAt, version, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonCacheRow &&
          other.id == this.id &&
          other.number == this.number &&
          other.seriesId == this.seriesId &&
          other.title == this.title &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class SeasonCacheRowsCompanion extends UpdateCompanion<SeasonCacheRow> {
  final Value<String> id;
  final Value<int> number;
  final Value<String> seriesId;
  final Value<String?> title;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const SeasonCacheRowsCompanion({
    this.id = const Value.absent(),
    this.number = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.title = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeasonCacheRowsCompanion.insert({
    required String id,
    required int number,
    required String seriesId,
    this.title = const Value.absent(),
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       number = Value(number),
       seriesId = Value(seriesId),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<SeasonCacheRow> custom({
    Expression<String>? id,
    Expression<int>? number,
    Expression<String>? seriesId,
    Expression<String>? title,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (number != null) 'number': number,
      if (seriesId != null) 'series_id': seriesId,
      if (title != null) 'title': title,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeasonCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<int>? number,
    Value<String>? seriesId,
    Value<String?>? title,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return SeasonCacheRowsCompanion(
      id: id ?? this.id,
      number: number ?? this.number,
      seriesId: seriesId ?? this.seriesId,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('seriesId: $seriesId, ')
          ..write('title: $title, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $SeasonCacheRowsTable seasonCacheRows = $SeasonCacheRowsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [seasonCacheRows];
}

typedef $$SeasonCacheRowsTableCreateCompanionBuilder =
    SeasonCacheRowsCompanion Function({
      required String id,
      required int number,
      required String seriesId,
      Value<String?> title,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$SeasonCacheRowsTableUpdateCompanionBuilder =
    SeasonCacheRowsCompanion Function({
      Value<String> id,
      Value<int> number,
      Value<String> seriesId,
      Value<String?> title,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$SeasonCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $SeasonCacheRowsTable> {
  $$SeasonCacheRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeasonCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $SeasonCacheRowsTable> {
  $$SeasonCacheRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeasonCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SeasonCacheRowsTable> {
  $$SeasonCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$SeasonCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SeasonCacheRowsTable,
          SeasonCacheRow,
          $$SeasonCacheRowsTableFilterComposer,
          $$SeasonCacheRowsTableOrderingComposer,
          $$SeasonCacheRowsTableAnnotationComposer,
          $$SeasonCacheRowsTableCreateCompanionBuilder,
          $$SeasonCacheRowsTableUpdateCompanionBuilder,
          (
            SeasonCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $SeasonCacheRowsTable,
              SeasonCacheRow
            >,
          ),
          SeasonCacheRow,
          PrefetchHooks Function()
        > {
  $$SeasonCacheRowsTableTableManager(
    _$CacheDatabase db,
    $SeasonCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeasonCacheRowsCompanion(
                id: id,
                number: number,
                seriesId: seriesId,
                title: title,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int number,
                required String seriesId,
                Value<String?> title = const Value.absent(),
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => SeasonCacheRowsCompanion.insert(
                id: id,
                number: number,
                seriesId: seriesId,
                title: title,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeasonCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SeasonCacheRowsTable,
      SeasonCacheRow,
      $$SeasonCacheRowsTableFilterComposer,
      $$SeasonCacheRowsTableOrderingComposer,
      $$SeasonCacheRowsTableAnnotationComposer,
      $$SeasonCacheRowsTableCreateCompanionBuilder,
      $$SeasonCacheRowsTableUpdateCompanionBuilder,
      (
        SeasonCacheRow,
        BaseReferences<_$CacheDatabase, $SeasonCacheRowsTable, SeasonCacheRow>,
      ),
      SeasonCacheRow,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$SeasonCacheRowsTableTableManager get seasonCacheRows =>
      $$SeasonCacheRowsTableTableManager(_db, _db.seasonCacheRows);
}
