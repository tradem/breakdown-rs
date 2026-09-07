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

class $BlockCacheRowsTable extends BlockCacheRows
    with TableInfo<$BlockCacheRowsTable, BlockCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockCacheRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<String> seasonId = GeneratedColumn<String>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    seasonId,
    seriesId,
    startDate,
    endDate,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'block_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlockCacheRow> instance, {
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
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    } else if (isInserting) {
      context.missing(_endDateMeta);
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
  BlockCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      )!,
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
  $BlockCacheRowsTable createAlias(String alias) {
    return $BlockCacheRowsTable(attachedDatabase, alias);
  }
}

class BlockCacheRow extends DataClass implements Insertable<BlockCacheRow> {
  /// Mirrors `BlockView.id`.
  final String id;

  /// Mirrors `BlockView.number`.
  final int number;

  /// Mirrors `BlockView.seasonId` (fetch scope: `GET /v1/blocks?season_id=`).
  final String seasonId;

  /// Mirrors `BlockView.seriesId` (opaque `SeriesId`, carried into
  /// `CreateEpisodeRequest` from the read DTO the user acts on).
  final String seriesId;

  /// Mirrors `BlockView.startDate` (wire string, preserved unchanged).
  final String startDate;

  /// Mirrors `BlockView.endDate` (wire string, preserved unchanged).
  final String endDate;

  /// Mirrors `BlockView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `BlockView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const BlockCacheRow({
    required this.id,
    required this.number,
    required this.seasonId,
    required this.seriesId,
    required this.startDate,
    required this.endDate,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['number'] = Variable<int>(number);
    map['season_id'] = Variable<String>(seasonId);
    map['series_id'] = Variable<String>(seriesId);
    map['start_date'] = Variable<String>(startDate);
    map['end_date'] = Variable<String>(endDate);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  BlockCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return BlockCacheRowsCompanion(
      id: Value(id),
      number: Value(number),
      seasonId: Value(seasonId),
      seriesId: Value(seriesId),
      startDate: Value(startDate),
      endDate: Value(endDate),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory BlockCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockCacheRow(
      id: serializer.fromJson<String>(json['id']),
      number: serializer.fromJson<int>(json['number']),
      seasonId: serializer.fromJson<String>(json['seasonId']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String>(json['endDate']),
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
      'seasonId': serializer.toJson<String>(seasonId),
      'seriesId': serializer.toJson<String>(seriesId),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String>(endDate),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  BlockCacheRow copyWith({
    String? id,
    int? number,
    String? seasonId,
    String? seriesId,
    String? startDate,
    String? endDate,
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => BlockCacheRow(
    id: id ?? this.id,
    number: number ?? this.number,
    seasonId: seasonId ?? this.seasonId,
    seriesId: seriesId ?? this.seriesId,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  BlockCacheRow copyWithCompanion(BlockCacheRowsCompanion data) {
    return BlockCacheRow(
      id: data.id.present ? data.id.value : this.id,
      number: data.number.present ? data.number.value : this.number,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockCacheRow(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('seasonId: $seasonId, ')
          ..write('seriesId: $seriesId, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    number,
    seasonId,
    seriesId,
    startDate,
    endDate,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockCacheRow &&
          other.id == this.id &&
          other.number == this.number &&
          other.seasonId == this.seasonId &&
          other.seriesId == this.seriesId &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class BlockCacheRowsCompanion extends UpdateCompanion<BlockCacheRow> {
  final Value<String> id;
  final Value<int> number;
  final Value<String> seasonId;
  final Value<String> seriesId;
  final Value<String> startDate;
  final Value<String> endDate;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const BlockCacheRowsCompanion({
    this.id = const Value.absent(),
    this.number = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockCacheRowsCompanion.insert({
    required String id,
    required int number,
    required String seasonId,
    required String seriesId,
    required String startDate,
    required String endDate,
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       number = Value(number),
       seasonId = Value(seasonId),
       seriesId = Value(seriesId),
       startDate = Value(startDate),
       endDate = Value(endDate),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<BlockCacheRow> custom({
    Expression<String>? id,
    Expression<int>? number,
    Expression<String>? seasonId,
    Expression<String>? seriesId,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (number != null) 'number': number,
      if (seasonId != null) 'season_id': seasonId,
      if (seriesId != null) 'series_id': seriesId,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<int>? number,
    Value<String>? seasonId,
    Value<String>? seriesId,
    Value<String>? startDate,
    Value<String>? endDate,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return BlockCacheRowsCompanion(
      id: id ?? this.id,
      number: number ?? this.number,
      seasonId: seasonId ?? this.seasonId,
      seriesId: seriesId ?? this.seriesId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
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
    if (seasonId.present) {
      map['season_id'] = Variable<String>(seasonId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
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
    return (StringBuffer('BlockCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('seasonId: $seasonId, ')
          ..write('seriesId: $seriesId, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodeCacheRowsTable extends EpisodeCacheRows
    with TableInfo<$EpisodeCacheRowsTable, EpisodeCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodeCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockIdMeta = const VerificationMeta(
    'blockId',
  );
  @override
  late final GeneratedColumn<String> blockId = GeneratedColumn<String>(
    'block_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    blockId,
    name,
    number,
    seriesId,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episode_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpisodeCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('block_id')) {
      context.handle(
        _blockIdMeta,
        blockId.isAcceptableOrUnknown(data['block_id']!, _blockIdMeta),
      );
    } else if (isInserting) {
      context.missing(_blockIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
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
  EpisodeCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      blockId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
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
  $EpisodeCacheRowsTable createAlias(String alias) {
    return $EpisodeCacheRowsTable(attachedDatabase, alias);
  }
}

class EpisodeCacheRow extends DataClass implements Insertable<EpisodeCacheRow> {
  /// Mirrors `EpisodeView.id`.
  final String id;

  /// Mirrors `EpisodeView.blockId` (fetch scope + `groupByBlock` key).
  final String blockId;

  /// Mirrors `EpisodeView.name` (nullable).
  final String? name;

  /// Mirrors `EpisodeView.number`.
  final int number;

  /// Mirrors `EpisodeView.seriesId` (opaque `SeriesId`).
  final String seriesId;

  /// Mirrors `EpisodeView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `EpisodeView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const EpisodeCacheRow({
    required this.id,
    required this.blockId,
    this.name,
    required this.number,
    required this.seriesId,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['block_id'] = Variable<String>(blockId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['number'] = Variable<int>(number);
    map['series_id'] = Variable<String>(seriesId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  EpisodeCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return EpisodeCacheRowsCompanion(
      id: Value(id),
      blockId: Value(blockId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      number: Value(number),
      seriesId: Value(seriesId),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory EpisodeCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeCacheRow(
      id: serializer.fromJson<String>(json['id']),
      blockId: serializer.fromJson<String>(json['blockId']),
      name: serializer.fromJson<String?>(json['name']),
      number: serializer.fromJson<int>(json['number']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
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
      'blockId': serializer.toJson<String>(blockId),
      'name': serializer.toJson<String?>(name),
      'number': serializer.toJson<int>(number),
      'seriesId': serializer.toJson<String>(seriesId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  EpisodeCacheRow copyWith({
    String? id,
    String? blockId,
    Value<String?> name = const Value.absent(),
    int? number,
    String? seriesId,
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => EpisodeCacheRow(
    id: id ?? this.id,
    blockId: blockId ?? this.blockId,
    name: name.present ? name.value : this.name,
    number: number ?? this.number,
    seriesId: seriesId ?? this.seriesId,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  EpisodeCacheRow copyWithCompanion(EpisodeCacheRowsCompanion data) {
    return EpisodeCacheRow(
      id: data.id.present ? data.id.value : this.id,
      blockId: data.blockId.present ? data.blockId.value : this.blockId,
      name: data.name.present ? data.name.value : this.name,
      number: data.number.present ? data.number.value : this.number,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeCacheRow(')
          ..write('id: $id, ')
          ..write('blockId: $blockId, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('seriesId: $seriesId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    blockId,
    name,
    number,
    seriesId,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeCacheRow &&
          other.id == this.id &&
          other.blockId == this.blockId &&
          other.name == this.name &&
          other.number == this.number &&
          other.seriesId == this.seriesId &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class EpisodeCacheRowsCompanion extends UpdateCompanion<EpisodeCacheRow> {
  final Value<String> id;
  final Value<String> blockId;
  final Value<String?> name;
  final Value<int> number;
  final Value<String> seriesId;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const EpisodeCacheRowsCompanion({
    this.id = const Value.absent(),
    this.blockId = const Value.absent(),
    this.name = const Value.absent(),
    this.number = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodeCacheRowsCompanion.insert({
    required String id,
    required String blockId,
    this.name = const Value.absent(),
    required int number,
    required String seriesId,
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       blockId = Value(blockId),
       number = Value(number),
       seriesId = Value(seriesId),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<EpisodeCacheRow> custom({
    Expression<String>? id,
    Expression<String>? blockId,
    Expression<String>? name,
    Expression<int>? number,
    Expression<String>? seriesId,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (blockId != null) 'block_id': blockId,
      if (name != null) 'name': name,
      if (number != null) 'number': number,
      if (seriesId != null) 'series_id': seriesId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodeCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? blockId,
    Value<String?>? name,
    Value<int>? number,
    Value<String>? seriesId,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return EpisodeCacheRowsCompanion(
      id: id ?? this.id,
      blockId: blockId ?? this.blockId,
      name: name ?? this.name,
      number: number ?? this.number,
      seriesId: seriesId ?? this.seriesId,
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
    if (blockId.present) {
      map['block_id'] = Variable<String>(blockId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
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
    return (StringBuffer('EpisodeCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('blockId: $blockId, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('seriesId: $seriesId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SceneCacheRowsTable extends SceneCacheRows
    with TableInfo<$SceneCacheRowsTable, SceneCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SceneCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<String> episodeId = GeneratedColumn<String>(
    'episode_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignedCharactersMeta =
      const VerificationMeta('assignedCharacters');
  @override
  late final GeneratedColumn<String> assignedCharacters =
      GeneratedColumn<String>(
        'assigned_characters',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _isScheduleSetMeta = const VerificationMeta(
    'isScheduleSet',
  );
  @override
  late final GeneratedColumn<bool> isScheduleSet = GeneratedColumn<bool>(
    'is_schedule_set',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_schedule_set" IN (0, 1))',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<String> mood = GeneratedColumn<String>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sceneNumberMeta = const VerificationMeta(
    'sceneNumber',
  );
  @override
  late final GeneratedColumn<int> sceneNumber = GeneratedColumn<int>(
    'scene_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scriptDayMeta = const VerificationMeta(
    'scriptDay',
  );
  @override
  late final GeneratedColumn<String> scriptDay = GeneratedColumn<String>(
    'script_day',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shootingDayIdsMeta = const VerificationMeta(
    'shootingDayIds',
  );
  @override
  late final GeneratedColumn<String> shootingDayIds = GeneratedColumn<String>(
    'shooting_day_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
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
    episodeId,
    assignedCharacters,
    isScheduleSet,
    location,
    mood,
    sceneNumber,
    scriptDay,
    shootingDayIds,
    summary,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scene_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SceneCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeIdMeta);
    }
    if (data.containsKey('assigned_characters')) {
      context.handle(
        _assignedCharactersMeta,
        assignedCharacters.isAcceptableOrUnknown(
          data['assigned_characters']!,
          _assignedCharactersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignedCharactersMeta);
    }
    if (data.containsKey('is_schedule_set')) {
      context.handle(
        _isScheduleSetMeta,
        isScheduleSet.isAcceptableOrUnknown(
          data['is_schedule_set']!,
          _isScheduleSetMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isScheduleSetMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('scene_number')) {
      context.handle(
        _sceneNumberMeta,
        sceneNumber.isAcceptableOrUnknown(
          data['scene_number']!,
          _sceneNumberMeta,
        ),
      );
    }
    if (data.containsKey('script_day')) {
      context.handle(
        _scriptDayMeta,
        scriptDay.isAcceptableOrUnknown(data['script_day']!, _scriptDayMeta),
      );
    }
    if (data.containsKey('shooting_day_ids')) {
      context.handle(
        _shootingDayIdsMeta,
        shootingDayIds.isAcceptableOrUnknown(
          data['shooting_day_ids']!,
          _shootingDayIdsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_shootingDayIdsMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
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
  SceneCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SceneCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_id'],
      )!,
      assignedCharacters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_characters'],
      )!,
      isScheduleSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_schedule_set'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mood'],
      ),
      sceneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scene_number'],
      ),
      scriptDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}script_day'],
      ),
      shootingDayIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shooting_day_ids'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
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
  $SceneCacheRowsTable createAlias(String alias) {
    return $SceneCacheRowsTable(attachedDatabase, alias);
  }
}

class SceneCacheRow extends DataClass implements Insertable<SceneCacheRow> {
  /// Mirrors `SceneView.id`.
  final String id;

  /// Mirrors `SceneView.episodeId` (fetch scope:
  /// `GET /v1/scenes?episode_id=`).
  final String episodeId;

  /// Mirrors `SceneView.assignedCharacters` (JSON-encoded id list;
  /// display count-only in Phase 1b, no mutation).
  final String assignedCharacters;

  /// Mirrors `SceneView.isScheduleSet`.
  final bool isScheduleSet;

  /// Mirrors `SceneView.location` (nullable, read-only detail data).
  final String? location;

  /// Mirrors `SceneView.mood` (nullable, read-only detail data).
  final String? mood;

  /// Mirrors `SceneView.sceneNumber` (nullable).
  final int? sceneNumber;

  /// Mirrors `SceneView.scriptDay` (nullable, read-only detail data).
  final String? scriptDay;

  /// Mirrors `SceneView.shootingDayIds` (JSON-encoded id list;
  /// display count-only in Phase 1b).
  final String shootingDayIds;

  /// Mirrors `SceneView.summary` (nullable, read-only detail data).
  final String? summary;

  /// Mirrors `SceneView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `SceneView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const SceneCacheRow({
    required this.id,
    required this.episodeId,
    required this.assignedCharacters,
    required this.isScheduleSet,
    this.location,
    this.mood,
    this.sceneNumber,
    this.scriptDay,
    required this.shootingDayIds,
    this.summary,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['episode_id'] = Variable<String>(episodeId);
    map['assigned_characters'] = Variable<String>(assignedCharacters);
    map['is_schedule_set'] = Variable<bool>(isScheduleSet);
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(mood);
    }
    if (!nullToAbsent || sceneNumber != null) {
      map['scene_number'] = Variable<int>(sceneNumber);
    }
    if (!nullToAbsent || scriptDay != null) {
      map['script_day'] = Variable<String>(scriptDay);
    }
    map['shooting_day_ids'] = Variable<String>(shootingDayIds);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  SceneCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return SceneCacheRowsCompanion(
      id: Value(id),
      episodeId: Value(episodeId),
      assignedCharacters: Value(assignedCharacters),
      isScheduleSet: Value(isScheduleSet),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      sceneNumber: sceneNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(sceneNumber),
      scriptDay: scriptDay == null && nullToAbsent
          ? const Value.absent()
          : Value(scriptDay),
      shootingDayIds: Value(shootingDayIds),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory SceneCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SceneCacheRow(
      id: serializer.fromJson<String>(json['id']),
      episodeId: serializer.fromJson<String>(json['episodeId']),
      assignedCharacters: serializer.fromJson<String>(
        json['assignedCharacters'],
      ),
      isScheduleSet: serializer.fromJson<bool>(json['isScheduleSet']),
      location: serializer.fromJson<String?>(json['location']),
      mood: serializer.fromJson<String?>(json['mood']),
      sceneNumber: serializer.fromJson<int?>(json['sceneNumber']),
      scriptDay: serializer.fromJson<String?>(json['scriptDay']),
      shootingDayIds: serializer.fromJson<String>(json['shootingDayIds']),
      summary: serializer.fromJson<String?>(json['summary']),
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
      'episodeId': serializer.toJson<String>(episodeId),
      'assignedCharacters': serializer.toJson<String>(assignedCharacters),
      'isScheduleSet': serializer.toJson<bool>(isScheduleSet),
      'location': serializer.toJson<String?>(location),
      'mood': serializer.toJson<String?>(mood),
      'sceneNumber': serializer.toJson<int?>(sceneNumber),
      'scriptDay': serializer.toJson<String?>(scriptDay),
      'shootingDayIds': serializer.toJson<String>(shootingDayIds),
      'summary': serializer.toJson<String?>(summary),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  SceneCacheRow copyWith({
    String? id,
    String? episodeId,
    String? assignedCharacters,
    bool? isScheduleSet,
    Value<String?> location = const Value.absent(),
    Value<String?> mood = const Value.absent(),
    Value<int?> sceneNumber = const Value.absent(),
    Value<String?> scriptDay = const Value.absent(),
    String? shootingDayIds,
    Value<String?> summary = const Value.absent(),
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => SceneCacheRow(
    id: id ?? this.id,
    episodeId: episodeId ?? this.episodeId,
    assignedCharacters: assignedCharacters ?? this.assignedCharacters,
    isScheduleSet: isScheduleSet ?? this.isScheduleSet,
    location: location.present ? location.value : this.location,
    mood: mood.present ? mood.value : this.mood,
    sceneNumber: sceneNumber.present ? sceneNumber.value : this.sceneNumber,
    scriptDay: scriptDay.present ? scriptDay.value : this.scriptDay,
    shootingDayIds: shootingDayIds ?? this.shootingDayIds,
    summary: summary.present ? summary.value : this.summary,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  SceneCacheRow copyWithCompanion(SceneCacheRowsCompanion data) {
    return SceneCacheRow(
      id: data.id.present ? data.id.value : this.id,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      assignedCharacters: data.assignedCharacters.present
          ? data.assignedCharacters.value
          : this.assignedCharacters,
      isScheduleSet: data.isScheduleSet.present
          ? data.isScheduleSet.value
          : this.isScheduleSet,
      location: data.location.present ? data.location.value : this.location,
      mood: data.mood.present ? data.mood.value : this.mood,
      sceneNumber: data.sceneNumber.present
          ? data.sceneNumber.value
          : this.sceneNumber,
      scriptDay: data.scriptDay.present ? data.scriptDay.value : this.scriptDay,
      shootingDayIds: data.shootingDayIds.present
          ? data.shootingDayIds.value
          : this.shootingDayIds,
      summary: data.summary.present ? data.summary.value : this.summary,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SceneCacheRow(')
          ..write('id: $id, ')
          ..write('episodeId: $episodeId, ')
          ..write('assignedCharacters: $assignedCharacters, ')
          ..write('isScheduleSet: $isScheduleSet, ')
          ..write('location: $location, ')
          ..write('mood: $mood, ')
          ..write('sceneNumber: $sceneNumber, ')
          ..write('scriptDay: $scriptDay, ')
          ..write('shootingDayIds: $shootingDayIds, ')
          ..write('summary: $summary, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    episodeId,
    assignedCharacters,
    isScheduleSet,
    location,
    mood,
    sceneNumber,
    scriptDay,
    shootingDayIds,
    summary,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneCacheRow &&
          other.id == this.id &&
          other.episodeId == this.episodeId &&
          other.assignedCharacters == this.assignedCharacters &&
          other.isScheduleSet == this.isScheduleSet &&
          other.location == this.location &&
          other.mood == this.mood &&
          other.sceneNumber == this.sceneNumber &&
          other.scriptDay == this.scriptDay &&
          other.shootingDayIds == this.shootingDayIds &&
          other.summary == this.summary &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class SceneCacheRowsCompanion extends UpdateCompanion<SceneCacheRow> {
  final Value<String> id;
  final Value<String> episodeId;
  final Value<String> assignedCharacters;
  final Value<bool> isScheduleSet;
  final Value<String?> location;
  final Value<String?> mood;
  final Value<int?> sceneNumber;
  final Value<String?> scriptDay;
  final Value<String> shootingDayIds;
  final Value<String?> summary;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const SceneCacheRowsCompanion({
    this.id = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.assignedCharacters = const Value.absent(),
    this.isScheduleSet = const Value.absent(),
    this.location = const Value.absent(),
    this.mood = const Value.absent(),
    this.sceneNumber = const Value.absent(),
    this.scriptDay = const Value.absent(),
    this.shootingDayIds = const Value.absent(),
    this.summary = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SceneCacheRowsCompanion.insert({
    required String id,
    required String episodeId,
    required String assignedCharacters,
    required bool isScheduleSet,
    this.location = const Value.absent(),
    this.mood = const Value.absent(),
    this.sceneNumber = const Value.absent(),
    this.scriptDay = const Value.absent(),
    required String shootingDayIds,
    this.summary = const Value.absent(),
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       episodeId = Value(episodeId),
       assignedCharacters = Value(assignedCharacters),
       isScheduleSet = Value(isScheduleSet),
       shootingDayIds = Value(shootingDayIds),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<SceneCacheRow> custom({
    Expression<String>? id,
    Expression<String>? episodeId,
    Expression<String>? assignedCharacters,
    Expression<bool>? isScheduleSet,
    Expression<String>? location,
    Expression<String>? mood,
    Expression<int>? sceneNumber,
    Expression<String>? scriptDay,
    Expression<String>? shootingDayIds,
    Expression<String>? summary,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (episodeId != null) 'episode_id': episodeId,
      if (assignedCharacters != null) 'assigned_characters': assignedCharacters,
      if (isScheduleSet != null) 'is_schedule_set': isScheduleSet,
      if (location != null) 'location': location,
      if (mood != null) 'mood': mood,
      if (sceneNumber != null) 'scene_number': sceneNumber,
      if (scriptDay != null) 'script_day': scriptDay,
      if (shootingDayIds != null) 'shooting_day_ids': shootingDayIds,
      if (summary != null) 'summary': summary,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SceneCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? episodeId,
    Value<String>? assignedCharacters,
    Value<bool>? isScheduleSet,
    Value<String?>? location,
    Value<String?>? mood,
    Value<int?>? sceneNumber,
    Value<String?>? scriptDay,
    Value<String>? shootingDayIds,
    Value<String?>? summary,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return SceneCacheRowsCompanion(
      id: id ?? this.id,
      episodeId: episodeId ?? this.episodeId,
      assignedCharacters: assignedCharacters ?? this.assignedCharacters,
      isScheduleSet: isScheduleSet ?? this.isScheduleSet,
      location: location ?? this.location,
      mood: mood ?? this.mood,
      sceneNumber: sceneNumber ?? this.sceneNumber,
      scriptDay: scriptDay ?? this.scriptDay,
      shootingDayIds: shootingDayIds ?? this.shootingDayIds,
      summary: summary ?? this.summary,
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
    if (episodeId.present) {
      map['episode_id'] = Variable<String>(episodeId.value);
    }
    if (assignedCharacters.present) {
      map['assigned_characters'] = Variable<String>(assignedCharacters.value);
    }
    if (isScheduleSet.present) {
      map['is_schedule_set'] = Variable<bool>(isScheduleSet.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (mood.present) {
      map['mood'] = Variable<String>(mood.value);
    }
    if (sceneNumber.present) {
      map['scene_number'] = Variable<int>(sceneNumber.value);
    }
    if (scriptDay.present) {
      map['script_day'] = Variable<String>(scriptDay.value);
    }
    if (shootingDayIds.present) {
      map['shooting_day_ids'] = Variable<String>(shootingDayIds.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
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
    return (StringBuffer('SceneCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('episodeId: $episodeId, ')
          ..write('assignedCharacters: $assignedCharacters, ')
          ..write('isScheduleSet: $isScheduleSet, ')
          ..write('location: $location, ')
          ..write('mood: $mood, ')
          ..write('sceneNumber: $sceneNumber, ')
          ..write('scriptDay: $scriptDay, ')
          ..write('shootingDayIds: $shootingDayIds, ')
          ..write('summary: $summary, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CostumeCategoryCacheRowsTable extends CostumeCategoryCacheRows
    with TableInfo<$CostumeCategoryCacheRowsTable, CostumeCategoryCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CostumeCategoryCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<String> seasonId = GeneratedColumn<String>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderKeyMeta = const VerificationMeta(
    'orderKey',
  );
  @override
  late final GeneratedColumn<String> orderKey = GeneratedColumn<String>(
    'order_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
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
    seasonId,
    name,
    orderKey,
    archived,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'costume_category_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CostumeCategoryCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('order_key')) {
      context.handle(
        _orderKeyMeta,
        orderKey.isAcceptableOrUnknown(data['order_key']!, _orderKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_orderKeyMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    } else if (isInserting) {
      context.missing(_archivedMeta);
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
  CostumeCategoryCacheRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CostumeCategoryCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      orderKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_key'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
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
  $CostumeCategoryCacheRowsTable createAlias(String alias) {
    return $CostumeCategoryCacheRowsTable(attachedDatabase, alias);
  }
}

class CostumeCategoryCacheRow extends DataClass
    implements Insertable<CostumeCategoryCacheRow> {
  /// Mirrors `CostumeCategoryView.id`.
  final String id;

  /// Mirrors `CostumeCategoryView.seasonId` (fetch scope:
  /// `GET /v1/seasons/{season_id}/costume-categories`).
  final String seasonId;

  /// Mirrors `CostumeCategoryView.name`.
  final String name;

  /// Mirrors `CostumeCategoryView.orderKey` (server `ORDER BY order_key
  /// ASC`; the client never re-sorts beyond presenting this key).
  final String orderKey;

  /// Mirrors `CostumeCategoryView.archived` (hidden behind the archived
  /// toggle, never silently unlisted).
  final bool archived;

  /// Mirrors `CostumeCategoryView.updatedAt` — server timestamp, preserved
  /// unchanged.
  final DateTime updatedAt;

  /// Mirrors `CostumeCategoryView.version` (rename echoes this row's
  /// version for optimistic locking).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const CostumeCategoryCacheRow({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.orderKey,
    required this.archived,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['season_id'] = Variable<String>(seasonId);
    map['name'] = Variable<String>(name);
    map['order_key'] = Variable<String>(orderKey);
    map['archived'] = Variable<bool>(archived);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CostumeCategoryCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return CostumeCategoryCacheRowsCompanion(
      id: Value(id),
      seasonId: Value(seasonId),
      name: Value(name),
      orderKey: Value(orderKey),
      archived: Value(archived),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory CostumeCategoryCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CostumeCategoryCacheRow(
      id: serializer.fromJson<String>(json['id']),
      seasonId: serializer.fromJson<String>(json['seasonId']),
      name: serializer.fromJson<String>(json['name']),
      orderKey: serializer.fromJson<String>(json['orderKey']),
      archived: serializer.fromJson<bool>(json['archived']),
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
      'seasonId': serializer.toJson<String>(seasonId),
      'name': serializer.toJson<String>(name),
      'orderKey': serializer.toJson<String>(orderKey),
      'archived': serializer.toJson<bool>(archived),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CostumeCategoryCacheRow copyWith({
    String? id,
    String? seasonId,
    String? name,
    String? orderKey,
    bool? archived,
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => CostumeCategoryCacheRow(
    id: id ?? this.id,
    seasonId: seasonId ?? this.seasonId,
    name: name ?? this.name,
    orderKey: orderKey ?? this.orderKey,
    archived: archived ?? this.archived,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CostumeCategoryCacheRow copyWithCompanion(
    CostumeCategoryCacheRowsCompanion data,
  ) {
    return CostumeCategoryCacheRow(
      id: data.id.present ? data.id.value : this.id,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      name: data.name.present ? data.name.value : this.name,
      orderKey: data.orderKey.present ? data.orderKey.value : this.orderKey,
      archived: data.archived.present ? data.archived.value : this.archived,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CostumeCategoryCacheRow(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('orderKey: $orderKey, ')
          ..write('archived: $archived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    name,
    orderKey,
    archived,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CostumeCategoryCacheRow &&
          other.id == this.id &&
          other.seasonId == this.seasonId &&
          other.name == this.name &&
          other.orderKey == this.orderKey &&
          other.archived == this.archived &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class CostumeCategoryCacheRowsCompanion
    extends UpdateCompanion<CostumeCategoryCacheRow> {
  final Value<String> id;
  final Value<String> seasonId;
  final Value<String> name;
  final Value<String> orderKey;
  final Value<bool> archived;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CostumeCategoryCacheRowsCompanion({
    this.id = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.name = const Value.absent(),
    this.orderKey = const Value.absent(),
    this.archived = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CostumeCategoryCacheRowsCompanion.insert({
    required String id,
    required String seasonId,
    required String name,
    required String orderKey,
    required bool archived,
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       seasonId = Value(seasonId),
       name = Value(name),
       orderKey = Value(orderKey),
       archived = Value(archived),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<CostumeCategoryCacheRow> custom({
    Expression<String>? id,
    Expression<String>? seasonId,
    Expression<String>? name,
    Expression<String>? orderKey,
    Expression<bool>? archived,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seasonId != null) 'season_id': seasonId,
      if (name != null) 'name': name,
      if (orderKey != null) 'order_key': orderKey,
      if (archived != null) 'archived': archived,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CostumeCategoryCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? seasonId,
    Value<String>? name,
    Value<String>? orderKey,
    Value<bool>? archived,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CostumeCategoryCacheRowsCompanion(
      id: id ?? this.id,
      seasonId: seasonId ?? this.seasonId,
      name: name ?? this.name,
      orderKey: orderKey ?? this.orderKey,
      archived: archived ?? this.archived,
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
    if (seasonId.present) {
      map['season_id'] = Variable<String>(seasonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (orderKey.present) {
      map['order_key'] = Variable<String>(orderKey.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
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
    return (StringBuffer('CostumeCategoryCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('orderKey: $orderKey, ')
          ..write('archived: $archived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CostumeCacheRowsTable extends CostumeCacheRows
    with TableInfo<$CostumeCacheRowsTable, CostumeCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CostumeCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<String> seasonId = GeneratedColumn<String>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photosJsonMeta = const VerificationMeta(
    'photosJson',
  );
  @override
  late final GeneratedColumn<String> photosJson = GeneratedColumn<String>(
    'photos_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _snapshotIndexMeta = const VerificationMeta(
    'snapshotIndex',
  );
  @override
  late final GeneratedColumn<int> snapshotIndex = GeneratedColumn<int>(
    'snapshot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seasonId,
    characterId,
    notes,
    detailsJson,
    photosJson,
    updatedAt,
    version,
    cachedAt,
    snapshotIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'costume_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CostumeCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    } else if (isInserting) {
      context.missing(_notesMeta);
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_detailsJsonMeta);
    }
    if (data.containsKey('photos_json')) {
      context.handle(
        _photosJsonMeta,
        photosJson.isAcceptableOrUnknown(data['photos_json']!, _photosJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_photosJsonMeta);
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
    if (data.containsKey('snapshot_index')) {
      context.handle(
        _snapshotIndexMeta,
        snapshotIndex.isAcceptableOrUnknown(
          data['snapshot_index']!,
          _snapshotIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CostumeCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CostumeCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      )!,
      photosJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photos_json'],
      )!,
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
      snapshotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_index'],
      )!,
    );
  }

  @override
  $CostumeCacheRowsTable createAlias(String alias) {
    return $CostumeCacheRowsTable(attachedDatabase, alias);
  }
}

class CostumeCacheRow extends DataClass implements Insertable<CostumeCacheRow> {
  /// Mirrors `CostumeView.id`.
  final String id;

  /// Fetch scope: `GET /v1/costumes?season_id=` (NOT on the wire DTO).
  final String seasonId;

  /// Mirrors `CostumeView.characterId` (nullable assignment).
  final String? characterId;

  /// Mirrors `CostumeView.notes`.
  final String notes;

  /// JSON snapshot of `CostumeView.details` (list of `CostumeDetailView`
  /// wire maps, serialized via the generated `breakdown_api` serializers).
  final String detailsJson;

  /// JSON snapshot of `CostumeView.photos` (list of `CostumePhotoView`
  /// wire maps, each with nested `variants`). Never cached independently —
  /// rides the costume row (no photo-list route).
  final String photosJson;

  /// Mirrors `CostumeView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `CostumeView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;

  /// Snapshot ordinal: position in the last `listBySeason` response
  /// (server `ORDER BY updated_at DESC`). SQLite does not guarantee row
  /// order without `ORDER BY`, so the snapshot index is persisted to
  /// reproduce the server order exactly, including `updated_at` ties.
  final int snapshotIndex;
  const CostumeCacheRow({
    required this.id,
    required this.seasonId,
    this.characterId,
    required this.notes,
    required this.detailsJson,
    required this.photosJson,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
    required this.snapshotIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['season_id'] = Variable<String>(seasonId);
    if (!nullToAbsent || characterId != null) {
      map['character_id'] = Variable<String>(characterId);
    }
    map['notes'] = Variable<String>(notes);
    map['details_json'] = Variable<String>(detailsJson);
    map['photos_json'] = Variable<String>(photosJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    map['snapshot_index'] = Variable<int>(snapshotIndex);
    return map;
  }

  CostumeCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return CostumeCacheRowsCompanion(
      id: Value(id),
      seasonId: Value(seasonId),
      characterId: characterId == null && nullToAbsent
          ? const Value.absent()
          : Value(characterId),
      notes: Value(notes),
      detailsJson: Value(detailsJson),
      photosJson: Value(photosJson),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
      snapshotIndex: Value(snapshotIndex),
    );
  }

  factory CostumeCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CostumeCacheRow(
      id: serializer.fromJson<String>(json['id']),
      seasonId: serializer.fromJson<String>(json['seasonId']),
      characterId: serializer.fromJson<String?>(json['characterId']),
      notes: serializer.fromJson<String>(json['notes']),
      detailsJson: serializer.fromJson<String>(json['detailsJson']),
      photosJson: serializer.fromJson<String>(json['photosJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      snapshotIndex: serializer.fromJson<int>(json['snapshotIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'seasonId': serializer.toJson<String>(seasonId),
      'characterId': serializer.toJson<String?>(characterId),
      'notes': serializer.toJson<String>(notes),
      'detailsJson': serializer.toJson<String>(detailsJson),
      'photosJson': serializer.toJson<String>(photosJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'snapshotIndex': serializer.toJson<int>(snapshotIndex),
    };
  }

  CostumeCacheRow copyWith({
    String? id,
    String? seasonId,
    Value<String?> characterId = const Value.absent(),
    String? notes,
    String? detailsJson,
    String? photosJson,
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
    int? snapshotIndex,
  }) => CostumeCacheRow(
    id: id ?? this.id,
    seasonId: seasonId ?? this.seasonId,
    characterId: characterId.present ? characterId.value : this.characterId,
    notes: notes ?? this.notes,
    detailsJson: detailsJson ?? this.detailsJson,
    photosJson: photosJson ?? this.photosJson,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
    snapshotIndex: snapshotIndex ?? this.snapshotIndex,
  );
  CostumeCacheRow copyWithCompanion(CostumeCacheRowsCompanion data) {
    return CostumeCacheRow(
      id: data.id.present ? data.id.value : this.id,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      notes: data.notes.present ? data.notes.value : this.notes,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
      photosJson: data.photosJson.present
          ? data.photosJson.value
          : this.photosJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      snapshotIndex: data.snapshotIndex.present
          ? data.snapshotIndex.value
          : this.snapshotIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CostumeCacheRow(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('characterId: $characterId, ')
          ..write('notes: $notes, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('photosJson: $photosJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('snapshotIndex: $snapshotIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    characterId,
    notes,
    detailsJson,
    photosJson,
    updatedAt,
    version,
    cachedAt,
    snapshotIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CostumeCacheRow &&
          other.id == this.id &&
          other.seasonId == this.seasonId &&
          other.characterId == this.characterId &&
          other.notes == this.notes &&
          other.detailsJson == this.detailsJson &&
          other.photosJson == this.photosJson &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt &&
          other.snapshotIndex == this.snapshotIndex);
}

class CostumeCacheRowsCompanion extends UpdateCompanion<CostumeCacheRow> {
  final Value<String> id;
  final Value<String> seasonId;
  final Value<String?> characterId;
  final Value<String> notes;
  final Value<String> detailsJson;
  final Value<String> photosJson;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> snapshotIndex;
  final Value<int> rowid;
  const CostumeCacheRowsCompanion({
    this.id = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.characterId = const Value.absent(),
    this.notes = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.photosJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.snapshotIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CostumeCacheRowsCompanion.insert({
    required String id,
    required String seasonId,
    this.characterId = const Value.absent(),
    required String notes,
    required String detailsJson,
    required String photosJson,
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    required int snapshotIndex,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       seasonId = Value(seasonId),
       notes = Value(notes),
       detailsJson = Value(detailsJson),
       photosJson = Value(photosJson),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt),
       snapshotIndex = Value(snapshotIndex);
  static Insertable<CostumeCacheRow> custom({
    Expression<String>? id,
    Expression<String>? seasonId,
    Expression<String>? characterId,
    Expression<String>? notes,
    Expression<String>? detailsJson,
    Expression<String>? photosJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? snapshotIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seasonId != null) 'season_id': seasonId,
      if (characterId != null) 'character_id': characterId,
      if (notes != null) 'notes': notes,
      if (detailsJson != null) 'details_json': detailsJson,
      if (photosJson != null) 'photos_json': photosJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (snapshotIndex != null) 'snapshot_index': snapshotIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CostumeCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? seasonId,
    Value<String?>? characterId,
    Value<String>? notes,
    Value<String>? detailsJson,
    Value<String>? photosJson,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? snapshotIndex,
    Value<int>? rowid,
  }) {
    return CostumeCacheRowsCompanion(
      id: id ?? this.id,
      seasonId: seasonId ?? this.seasonId,
      characterId: characterId ?? this.characterId,
      notes: notes ?? this.notes,
      detailsJson: detailsJson ?? this.detailsJson,
      photosJson: photosJson ?? this.photosJson,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      cachedAt: cachedAt ?? this.cachedAt,
      snapshotIndex: snapshotIndex ?? this.snapshotIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (seasonId.present) {
      map['season_id'] = Variable<String>(seasonId.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (photosJson.present) {
      map['photos_json'] = Variable<String>(photosJson.value);
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
    if (snapshotIndex.present) {
      map['snapshot_index'] = Variable<int>(snapshotIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CostumeCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('characterId: $characterId, ')
          ..write('notes: $notes, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('photosJson: $photosJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('snapshotIndex: $snapshotIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CharacterCacheRowsTable extends CharacterCacheRows
    with TableInfo<$CharacterCacheRowsTable, CharacterCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<String> seasonId = GeneratedColumn<String>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<String> height = GeneratedColumn<String>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<String> weight = GeneratedColumn<String>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chestMeta = const VerificationMeta('chest');
  @override
  late final GeneratedColumn<String> chest = GeneratedColumn<String>(
    'chest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _waistMeta = const VerificationMeta('waist');
  @override
  late final GeneratedColumn<String> waist = GeneratedColumn<String>(
    'waist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hipsMeta = const VerificationMeta('hips');
  @override
  late final GeneratedColumn<String> hips = GeneratedColumn<String>(
    'hips',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shoeSizeMeta = const VerificationMeta(
    'shoeSize',
  );
  @override
  late final GeneratedColumn<String> shoeSize = GeneratedColumn<String>(
    'shoe_size',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hatSizeMeta = const VerificationMeta(
    'hatSize',
  );
  @override
  late final GeneratedColumn<String> hatSize = GeneratedColumn<String>(
    'hat_size',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
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
    seasonId,
    name,
    category,
    height,
    weight,
    chest,
    waist,
    hips,
    shoeSize,
    hatSize,
    email,
    phone,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    } else if (isInserting) {
      context.missing(_weightMeta);
    }
    if (data.containsKey('chest')) {
      context.handle(
        _chestMeta,
        chest.isAcceptableOrUnknown(data['chest']!, _chestMeta),
      );
    } else if (isInserting) {
      context.missing(_chestMeta);
    }
    if (data.containsKey('waist')) {
      context.handle(
        _waistMeta,
        waist.isAcceptableOrUnknown(data['waist']!, _waistMeta),
      );
    } else if (isInserting) {
      context.missing(_waistMeta);
    }
    if (data.containsKey('hips')) {
      context.handle(
        _hipsMeta,
        hips.isAcceptableOrUnknown(data['hips']!, _hipsMeta),
      );
    } else if (isInserting) {
      context.missing(_hipsMeta);
    }
    if (data.containsKey('shoe_size')) {
      context.handle(
        _shoeSizeMeta,
        shoeSize.isAcceptableOrUnknown(data['shoe_size']!, _shoeSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_shoeSizeMeta);
    }
    if (data.containsKey('hat_size')) {
      context.handle(
        _hatSizeMeta,
        hatSize.isAcceptableOrUnknown(data['hat_size']!, _hatSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_hatSizeMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
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
  CharacterCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}height'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weight'],
      )!,
      chest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chest'],
      )!,
      waist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waist'],
      )!,
      hips: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hips'],
      )!,
      shoeSize: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shoe_size'],
      )!,
      hatSize: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hat_size'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
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
  $CharacterCacheRowsTable createAlias(String alias) {
    return $CharacterCacheRowsTable(attachedDatabase, alias);
  }
}

class CharacterCacheRow extends DataClass
    implements Insertable<CharacterCacheRow> {
  /// Mirrors `CharacterView.id`.
  final String id;

  /// Mirrors `CharacterView.seasonId` (fetch scope).
  final String seasonId;

  /// Mirrors `CharacterView.name`.
  final String name;

  /// Mirrors `CharacterView.category` (`main_cast|guest|extra` wire string;
  /// unknown variants strictly reject at parse time, never guessed).
  final String category;

  /// Flattened `CharacterMeasurements` (all seven required strings).
  final String height;
  final String weight;
  final String chest;
  final String waist;
  final String hips;
  final String shoeSize;
  final String hatSize;

  /// Flattened `ContactInfo` (both nullable).
  final String? email;
  final String? phone;

  /// Mirrors `CharacterView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `CharacterView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const CharacterCacheRow({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.category,
    required this.height,
    required this.weight,
    required this.chest,
    required this.waist,
    required this.hips,
    required this.shoeSize,
    required this.hatSize,
    this.email,
    this.phone,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['season_id'] = Variable<String>(seasonId);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    map['height'] = Variable<String>(height);
    map['weight'] = Variable<String>(weight);
    map['chest'] = Variable<String>(chest);
    map['waist'] = Variable<String>(waist);
    map['hips'] = Variable<String>(hips);
    map['shoe_size'] = Variable<String>(shoeSize);
    map['hat_size'] = Variable<String>(hatSize);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CharacterCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return CharacterCacheRowsCompanion(
      id: Value(id),
      seasonId: Value(seasonId),
      name: Value(name),
      category: Value(category),
      height: Value(height),
      weight: Value(weight),
      chest: Value(chest),
      waist: Value(waist),
      hips: Value(hips),
      shoeSize: Value(shoeSize),
      hatSize: Value(hatSize),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory CharacterCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterCacheRow(
      id: serializer.fromJson<String>(json['id']),
      seasonId: serializer.fromJson<String>(json['seasonId']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      height: serializer.fromJson<String>(json['height']),
      weight: serializer.fromJson<String>(json['weight']),
      chest: serializer.fromJson<String>(json['chest']),
      waist: serializer.fromJson<String>(json['waist']),
      hips: serializer.fromJson<String>(json['hips']),
      shoeSize: serializer.fromJson<String>(json['shoeSize']),
      hatSize: serializer.fromJson<String>(json['hatSize']),
      email: serializer.fromJson<String?>(json['email']),
      phone: serializer.fromJson<String?>(json['phone']),
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
      'seasonId': serializer.toJson<String>(seasonId),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'height': serializer.toJson<String>(height),
      'weight': serializer.toJson<String>(weight),
      'chest': serializer.toJson<String>(chest),
      'waist': serializer.toJson<String>(waist),
      'hips': serializer.toJson<String>(hips),
      'shoeSize': serializer.toJson<String>(shoeSize),
      'hatSize': serializer.toJson<String>(hatSize),
      'email': serializer.toJson<String?>(email),
      'phone': serializer.toJson<String?>(phone),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CharacterCacheRow copyWith({
    String? id,
    String? seasonId,
    String? name,
    String? category,
    String? height,
    String? weight,
    String? chest,
    String? waist,
    String? hips,
    String? shoeSize,
    String? hatSize,
    Value<String?> email = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => CharacterCacheRow(
    id: id ?? this.id,
    seasonId: seasonId ?? this.seasonId,
    name: name ?? this.name,
    category: category ?? this.category,
    height: height ?? this.height,
    weight: weight ?? this.weight,
    chest: chest ?? this.chest,
    waist: waist ?? this.waist,
    hips: hips ?? this.hips,
    shoeSize: shoeSize ?? this.shoeSize,
    hatSize: hatSize ?? this.hatSize,
    email: email.present ? email.value : this.email,
    phone: phone.present ? phone.value : this.phone,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CharacterCacheRow copyWithCompanion(CharacterCacheRowsCompanion data) {
    return CharacterCacheRow(
      id: data.id.present ? data.id.value : this.id,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      height: data.height.present ? data.height.value : this.height,
      weight: data.weight.present ? data.weight.value : this.weight,
      chest: data.chest.present ? data.chest.value : this.chest,
      waist: data.waist.present ? data.waist.value : this.waist,
      hips: data.hips.present ? data.hips.value : this.hips,
      shoeSize: data.shoeSize.present ? data.shoeSize.value : this.shoeSize,
      hatSize: data.hatSize.present ? data.hatSize.value : this.hatSize,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterCacheRow(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('height: $height, ')
          ..write('weight: $weight, ')
          ..write('chest: $chest, ')
          ..write('waist: $waist, ')
          ..write('hips: $hips, ')
          ..write('shoeSize: $shoeSize, ')
          ..write('hatSize: $hatSize, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    name,
    category,
    height,
    weight,
    chest,
    waist,
    hips,
    shoeSize,
    hatSize,
    email,
    phone,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterCacheRow &&
          other.id == this.id &&
          other.seasonId == this.seasonId &&
          other.name == this.name &&
          other.category == this.category &&
          other.height == this.height &&
          other.weight == this.weight &&
          other.chest == this.chest &&
          other.waist == this.waist &&
          other.hips == this.hips &&
          other.shoeSize == this.shoeSize &&
          other.hatSize == this.hatSize &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class CharacterCacheRowsCompanion extends UpdateCompanion<CharacterCacheRow> {
  final Value<String> id;
  final Value<String> seasonId;
  final Value<String> name;
  final Value<String> category;
  final Value<String> height;
  final Value<String> weight;
  final Value<String> chest;
  final Value<String> waist;
  final Value<String> hips;
  final Value<String> shoeSize;
  final Value<String> hatSize;
  final Value<String?> email;
  final Value<String?> phone;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CharacterCacheRowsCompanion({
    this.id = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.height = const Value.absent(),
    this.weight = const Value.absent(),
    this.chest = const Value.absent(),
    this.waist = const Value.absent(),
    this.hips = const Value.absent(),
    this.shoeSize = const Value.absent(),
    this.hatSize = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharacterCacheRowsCompanion.insert({
    required String id,
    required String seasonId,
    required String name,
    required String category,
    required String height,
    required String weight,
    required String chest,
    required String waist,
    required String hips,
    required String shoeSize,
    required String hatSize,
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       seasonId = Value(seasonId),
       name = Value(name),
       category = Value(category),
       height = Value(height),
       weight = Value(weight),
       chest = Value(chest),
       waist = Value(waist),
       hips = Value(hips),
       shoeSize = Value(shoeSize),
       hatSize = Value(hatSize),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<CharacterCacheRow> custom({
    Expression<String>? id,
    Expression<String>? seasonId,
    Expression<String>? name,
    Expression<String>? category,
    Expression<String>? height,
    Expression<String>? weight,
    Expression<String>? chest,
    Expression<String>? waist,
    Expression<String>? hips,
    Expression<String>? shoeSize,
    Expression<String>? hatSize,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seasonId != null) 'season_id': seasonId,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (height != null) 'height': height,
      if (weight != null) 'weight': weight,
      if (chest != null) 'chest': chest,
      if (waist != null) 'waist': waist,
      if (hips != null) 'hips': hips,
      if (shoeSize != null) 'shoe_size': shoeSize,
      if (hatSize != null) 'hat_size': hatSize,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharacterCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? seasonId,
    Value<String>? name,
    Value<String>? category,
    Value<String>? height,
    Value<String>? weight,
    Value<String>? chest,
    Value<String>? waist,
    Value<String>? hips,
    Value<String>? shoeSize,
    Value<String>? hatSize,
    Value<String?>? email,
    Value<String?>? phone,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CharacterCacheRowsCompanion(
      id: id ?? this.id,
      seasonId: seasonId ?? this.seasonId,
      name: name ?? this.name,
      category: category ?? this.category,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      chest: chest ?? this.chest,
      waist: waist ?? this.waist,
      hips: hips ?? this.hips,
      shoeSize: shoeSize ?? this.shoeSize,
      hatSize: hatSize ?? this.hatSize,
      email: email ?? this.email,
      phone: phone ?? this.phone,
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
    if (seasonId.present) {
      map['season_id'] = Variable<String>(seasonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (height.present) {
      map['height'] = Variable<String>(height.value);
    }
    if (weight.present) {
      map['weight'] = Variable<String>(weight.value);
    }
    if (chest.present) {
      map['chest'] = Variable<String>(chest.value);
    }
    if (waist.present) {
      map['waist'] = Variable<String>(waist.value);
    }
    if (hips.present) {
      map['hips'] = Variable<String>(hips.value);
    }
    if (shoeSize.present) {
      map['shoe_size'] = Variable<String>(shoeSize.value);
    }
    if (hatSize.present) {
      map['hat_size'] = Variable<String>(hatSize.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
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
    return (StringBuffer('CharacterCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('height: $height, ')
          ..write('weight: $weight, ')
          ..write('chest: $chest, ')
          ..write('waist: $waist, ')
          ..write('hips: $hips, ')
          ..write('shoeSize: $shoeSize, ')
          ..write('hatSize: $hatSize, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShootingDayCacheRowsTable extends ShootingDayCacheRows
    with TableInfo<$ShootingDayCacheRowsTable, ShootingDayCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShootingDayCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<String> episodeId = GeneratedColumn<String>(
    'episode_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderKeyMeta = const VerificationMeta(
    'orderKey',
  );
  @override
  late final GeneratedColumn<String> orderKey = GeneratedColumn<String>(
    'order_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceJsonMeta = const VerificationMeta(
    'sourceJson',
  );
  @override
  late final GeneratedColumn<String> sourceJson = GeneratedColumn<String>(
    'source_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
  );
  static const VerificationMeta _wrappedAtMeta = const VerificationMeta(
    'wrappedAt',
  );
  @override
  late final GeneratedColumn<DateTime> wrappedAt = GeneratedColumn<DateTime>(
    'wrapped_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
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
    episodeId,
    orderKey,
    sourceJson,
    label,
    date,
    archived,
    wrappedAt,
    updatedAt,
    version,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shooting_day_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShootingDayCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeIdMeta);
    }
    if (data.containsKey('order_key')) {
      context.handle(
        _orderKeyMeta,
        orderKey.isAcceptableOrUnknown(data['order_key']!, _orderKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_orderKeyMeta);
    }
    if (data.containsKey('source_json')) {
      context.handle(
        _sourceJsonMeta,
        sourceJson.isAcceptableOrUnknown(data['source_json']!, _sourceJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceJsonMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    } else if (isInserting) {
      context.missing(_archivedMeta);
    }
    if (data.containsKey('wrapped_at')) {
      context.handle(
        _wrappedAtMeta,
        wrappedAt.isAcceptableOrUnknown(data['wrapped_at']!, _wrappedAtMeta),
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
  ShootingDayCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShootingDayCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_id'],
      )!,
      orderKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_key'],
      )!,
      sourceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_json'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      wrappedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}wrapped_at'],
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
  $ShootingDayCacheRowsTable createAlias(String alias) {
    return $ShootingDayCacheRowsTable(attachedDatabase, alias);
  }
}

class ShootingDayCacheRow extends DataClass
    implements Insertable<ShootingDayCacheRow> {
  /// Mirrors `ShootingDayView.id`.
  final String id;

  /// Mirrors `ShootingDayView.episodeId` (fetch scope).
  final String episodeId;

  /// Mirrors `ShootingDayView.orderKey` (server `ORDER BY order_key ASC`;
  /// the client never re-sorts).
  final String orderKey;

  /// Mirrors `ShootingDayView.source` as wire JSON (`"Manual"` or
  /// `{"AiExtracted":{...}}`). Stored verbatim so future variants survive.
  final String sourceJson;

  /// Mirrors `ShootingDayView.label` (nullable).
  final String? label;

  /// Mirrors `ShootingDayView.date` as ISO-8601 `yyyy-MM-dd` text (nullable;
  /// `null` = unscheduled. Distinct from absent — see update semantics).
  final String? date;

  /// Mirrors `ShootingDayView.archived`.
  final bool archived;

  /// Mirrors `ShootingDayView.wrappedAt` (nullable — `None` means open).
  final DateTime? wrappedAt;

  /// Mirrors `ShootingDayView.updatedAt` — server timestamp, preserved.
  final DateTime updatedAt;

  /// Mirrors `ShootingDayView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;
  const ShootingDayCacheRow({
    required this.id,
    required this.episodeId,
    required this.orderKey,
    required this.sourceJson,
    this.label,
    this.date,
    required this.archived,
    this.wrappedAt,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['episode_id'] = Variable<String>(episodeId);
    map['order_key'] = Variable<String>(orderKey);
    map['source_json'] = Variable<String>(sourceJson);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    if (!nullToAbsent || date != null) {
      map['date'] = Variable<String>(date);
    }
    map['archived'] = Variable<bool>(archived);
    if (!nullToAbsent || wrappedAt != null) {
      map['wrapped_at'] = Variable<DateTime>(wrappedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  ShootingDayCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return ShootingDayCacheRowsCompanion(
      id: Value(id),
      episodeId: Value(episodeId),
      orderKey: Value(orderKey),
      sourceJson: Value(sourceJson),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      date: date == null && nullToAbsent ? const Value.absent() : Value(date),
      archived: Value(archived),
      wrappedAt: wrappedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(wrappedAt),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
    );
  }

  factory ShootingDayCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShootingDayCacheRow(
      id: serializer.fromJson<String>(json['id']),
      episodeId: serializer.fromJson<String>(json['episodeId']),
      orderKey: serializer.fromJson<String>(json['orderKey']),
      sourceJson: serializer.fromJson<String>(json['sourceJson']),
      label: serializer.fromJson<String?>(json['label']),
      date: serializer.fromJson<String?>(json['date']),
      archived: serializer.fromJson<bool>(json['archived']),
      wrappedAt: serializer.fromJson<DateTime?>(json['wrappedAt']),
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
      'episodeId': serializer.toJson<String>(episodeId),
      'orderKey': serializer.toJson<String>(orderKey),
      'sourceJson': serializer.toJson<String>(sourceJson),
      'label': serializer.toJson<String?>(label),
      'date': serializer.toJson<String?>(date),
      'archived': serializer.toJson<bool>(archived),
      'wrappedAt': serializer.toJson<DateTime?>(wrappedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  ShootingDayCacheRow copyWith({
    String? id,
    String? episodeId,
    String? orderKey,
    String? sourceJson,
    Value<String?> label = const Value.absent(),
    Value<String?> date = const Value.absent(),
    bool? archived,
    Value<DateTime?> wrappedAt = const Value.absent(),
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
  }) => ShootingDayCacheRow(
    id: id ?? this.id,
    episodeId: episodeId ?? this.episodeId,
    orderKey: orderKey ?? this.orderKey,
    sourceJson: sourceJson ?? this.sourceJson,
    label: label.present ? label.value : this.label,
    date: date.present ? date.value : this.date,
    archived: archived ?? this.archived,
    wrappedAt: wrappedAt.present ? wrappedAt.value : this.wrappedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  ShootingDayCacheRow copyWithCompanion(ShootingDayCacheRowsCompanion data) {
    return ShootingDayCacheRow(
      id: data.id.present ? data.id.value : this.id,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      orderKey: data.orderKey.present ? data.orderKey.value : this.orderKey,
      sourceJson: data.sourceJson.present
          ? data.sourceJson.value
          : this.sourceJson,
      label: data.label.present ? data.label.value : this.label,
      date: data.date.present ? data.date.value : this.date,
      archived: data.archived.present ? data.archived.value : this.archived,
      wrappedAt: data.wrappedAt.present ? data.wrappedAt.value : this.wrappedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShootingDayCacheRow(')
          ..write('id: $id, ')
          ..write('episodeId: $episodeId, ')
          ..write('orderKey: $orderKey, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('label: $label, ')
          ..write('date: $date, ')
          ..write('archived: $archived, ')
          ..write('wrappedAt: $wrappedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    episodeId,
    orderKey,
    sourceJson,
    label,
    date,
    archived,
    wrappedAt,
    updatedAt,
    version,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShootingDayCacheRow &&
          other.id == this.id &&
          other.episodeId == this.episodeId &&
          other.orderKey == this.orderKey &&
          other.sourceJson == this.sourceJson &&
          other.label == this.label &&
          other.date == this.date &&
          other.archived == this.archived &&
          other.wrappedAt == this.wrappedAt &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt);
}

class ShootingDayCacheRowsCompanion
    extends UpdateCompanion<ShootingDayCacheRow> {
  final Value<String> id;
  final Value<String> episodeId;
  final Value<String> orderKey;
  final Value<String> sourceJson;
  final Value<String?> label;
  final Value<String?> date;
  final Value<bool> archived;
  final Value<DateTime?> wrappedAt;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const ShootingDayCacheRowsCompanion({
    this.id = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.orderKey = const Value.absent(),
    this.sourceJson = const Value.absent(),
    this.label = const Value.absent(),
    this.date = const Value.absent(),
    this.archived = const Value.absent(),
    this.wrappedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShootingDayCacheRowsCompanion.insert({
    required String id,
    required String episodeId,
    required String orderKey,
    required String sourceJson,
    this.label = const Value.absent(),
    this.date = const Value.absent(),
    required bool archived,
    this.wrappedAt = const Value.absent(),
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       episodeId = Value(episodeId),
       orderKey = Value(orderKey),
       sourceJson = Value(sourceJson),
       archived = Value(archived),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt);
  static Insertable<ShootingDayCacheRow> custom({
    Expression<String>? id,
    Expression<String>? episodeId,
    Expression<String>? orderKey,
    Expression<String>? sourceJson,
    Expression<String>? label,
    Expression<String>? date,
    Expression<bool>? archived,
    Expression<DateTime>? wrappedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (episodeId != null) 'episode_id': episodeId,
      if (orderKey != null) 'order_key': orderKey,
      if (sourceJson != null) 'source_json': sourceJson,
      if (label != null) 'label': label,
      if (date != null) 'date': date,
      if (archived != null) 'archived': archived,
      if (wrappedAt != null) 'wrapped_at': wrappedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShootingDayCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? episodeId,
    Value<String>? orderKey,
    Value<String>? sourceJson,
    Value<String?>? label,
    Value<String?>? date,
    Value<bool>? archived,
    Value<DateTime?>? wrappedAt,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return ShootingDayCacheRowsCompanion(
      id: id ?? this.id,
      episodeId: episodeId ?? this.episodeId,
      orderKey: orderKey ?? this.orderKey,
      sourceJson: sourceJson ?? this.sourceJson,
      label: label ?? this.label,
      date: date ?? this.date,
      archived: archived ?? this.archived,
      wrappedAt: wrappedAt ?? this.wrappedAt,
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
    if (episodeId.present) {
      map['episode_id'] = Variable<String>(episodeId.value);
    }
    if (orderKey.present) {
      map['order_key'] = Variable<String>(orderKey.value);
    }
    if (sourceJson.present) {
      map['source_json'] = Variable<String>(sourceJson.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (wrappedAt.present) {
      map['wrapped_at'] = Variable<DateTime>(wrappedAt.value);
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
    return (StringBuffer('ShootingDayCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('episodeId: $episodeId, ')
          ..write('orderKey: $orderKey, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('label: $label, ')
          ..write('date: $date, ')
          ..write('archived: $archived, ')
          ..write('wrappedAt: $wrappedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SceneShootCacheRowsTable extends SceneShootCacheRows
    with TableInfo<$SceneShootCacheRowsTable, SceneShootCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SceneShootCacheRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shootingDayIdMeta = const VerificationMeta(
    'shootingDayId',
  );
  @override
  late final GeneratedColumn<String> shootingDayId = GeneratedColumn<String>(
    'shooting_day_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sceneIdMeta = const VerificationMeta(
    'sceneId',
  );
  @override
  late final GeneratedColumn<String> sceneId = GeneratedColumn<String>(
    'scene_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plannedOrderMeta = const VerificationMeta(
    'plannedOrder',
  );
  @override
  late final GeneratedColumn<String> plannedOrder = GeneratedColumn<String>(
    'planned_order',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualOrderMeta = const VerificationMeta(
    'actualOrder',
  );
  @override
  late final GeneratedColumn<String> actualOrder = GeneratedColumn<String>(
    'actual_order',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDtMeta = const VerificationMeta(
    'startDt',
  );
  @override
  late final GeneratedColumn<DateTime> startDt = GeneratedColumn<DateTime>(
    'start_dt',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endDtMeta = const VerificationMeta('endDt');
  @override
  late final GeneratedColumn<DateTime> endDt = GeneratedColumn<DateTime>(
    'end_dt',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesJsonMeta = const VerificationMeta(
    'notesJson',
  );
  @override
  late final GeneratedColumn<String> notesJson = GeneratedColumn<String>(
    'notes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _continuityPhotoIdsJsonMeta =
      const VerificationMeta('continuityPhotoIdsJson');
  @override
  late final GeneratedColumn<String> continuityPhotoIdsJson =
      GeneratedColumn<String>(
        'continuity_photo_ids_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
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
  static const VerificationMeta _snapshotIndexMeta = const VerificationMeta(
    'snapshotIndex',
  );
  @override
  late final GeneratedColumn<int> snapshotIndex = GeneratedColumn<int>(
    'snapshot_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shootingDayId,
    sceneId,
    plannedOrder,
    actualOrder,
    status,
    startDt,
    endDt,
    notesJson,
    continuityPhotoIdsJson,
    updatedAt,
    version,
    cachedAt,
    snapshotIndex,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scene_shoot_cache_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SceneShootCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('shooting_day_id')) {
      context.handle(
        _shootingDayIdMeta,
        shootingDayId.isAcceptableOrUnknown(
          data['shooting_day_id']!,
          _shootingDayIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_shootingDayIdMeta);
    }
    if (data.containsKey('scene_id')) {
      context.handle(
        _sceneIdMeta,
        sceneId.isAcceptableOrUnknown(data['scene_id']!, _sceneIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sceneIdMeta);
    }
    if (data.containsKey('planned_order')) {
      context.handle(
        _plannedOrderMeta,
        plannedOrder.isAcceptableOrUnknown(
          data['planned_order']!,
          _plannedOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plannedOrderMeta);
    }
    if (data.containsKey('actual_order')) {
      context.handle(
        _actualOrderMeta,
        actualOrder.isAcceptableOrUnknown(
          data['actual_order']!,
          _actualOrderMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('start_dt')) {
      context.handle(
        _startDtMeta,
        startDt.isAcceptableOrUnknown(data['start_dt']!, _startDtMeta),
      );
    }
    if (data.containsKey('end_dt')) {
      context.handle(
        _endDtMeta,
        endDt.isAcceptableOrUnknown(data['end_dt']!, _endDtMeta),
      );
    }
    if (data.containsKey('notes_json')) {
      context.handle(
        _notesJsonMeta,
        notesJson.isAcceptableOrUnknown(data['notes_json']!, _notesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_notesJsonMeta);
    }
    if (data.containsKey('continuity_photo_ids_json')) {
      context.handle(
        _continuityPhotoIdsJsonMeta,
        continuityPhotoIdsJson.isAcceptableOrUnknown(
          data['continuity_photo_ids_json']!,
          _continuityPhotoIdsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_continuityPhotoIdsJsonMeta);
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
    if (data.containsKey('snapshot_index')) {
      context.handle(
        _snapshotIndexMeta,
        snapshotIndex.isAcceptableOrUnknown(
          data['snapshot_index']!,
          _snapshotIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SceneShootCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SceneShootCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shootingDayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shooting_day_id'],
      )!,
      sceneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scene_id'],
      )!,
      plannedOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}planned_order'],
      )!,
      actualOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actual_order'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startDt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_dt'],
      ),
      endDt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_dt'],
      ),
      notesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes_json'],
      )!,
      continuityPhotoIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}continuity_photo_ids_json'],
      )!,
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
      snapshotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_index'],
      )!,
    );
  }

  @override
  $SceneShootCacheRowsTable createAlias(String alias) {
    return $SceneShootCacheRowsTable(attachedDatabase, alias);
  }
}

class SceneShootCacheRow extends DataClass
    implements Insertable<SceneShootCacheRow> {
  /// Mirrors `SceneShootView.id`.
  final String id;

  /// Fetch scope: the shooting day (`list_by_shooting_day`, natively on
  /// the DTO as `shootingDayId`).
  final String shootingDayId;

  /// Mirrors `SceneShootView.sceneId` (the pair's scene side).
  final String sceneId;

  /// Mirrors `SceneShootView.plannedOrder` (Soll position key).
  final String plannedOrder;

  /// Mirrors `SceneShootView.actualOrder` (Ist position key, nullable —
  /// `null` means execution has not rearranged this shoot).
  final String? actualOrder;

  /// Mirrors `SceneShootView.status` as the wire string
  /// (`Planned|Scheduled|InProgress|Shot|Skipped`; unknown variants
  /// strictly reject at parse time, never guessed).
  final String status;

  /// Mirrors `SceneShootView.startDt` (nullable — `null` means not started).
  final DateTime? startDt;

  /// Mirrors `SceneShootView.endDt` (nullable — `null` means not finished).
  final DateTime? endDt;

  /// JSON snapshot of `SceneShootView.notes` (list of `SerializedNote`
  /// wire maps, serialized via the generated `breakdown_api` serializers).
  final String notesJson;

  /// JSON snapshot of `SceneShootView.continuityPhotoIds` (plain id list).
  final String continuityPhotoIdsJson;

  /// Mirrors `SceneShootView.updatedAt` — server timestamp, preserved unchanged.
  final DateTime updatedAt;

  /// Mirrors `SceneShootView.version` (optimistic-locking round-trips).
  final int version;

  /// Client-only cache-write time. TTL is computed from this column only.
  final DateTime cachedAt;

  /// Snapshot ordinal: position in the last `listShoots` response
  /// (server `ORDER BY COALESCE(actual_order, planned_order) ASC`).
  final int snapshotIndex;
  const SceneShootCacheRow({
    required this.id,
    required this.shootingDayId,
    required this.sceneId,
    required this.plannedOrder,
    this.actualOrder,
    required this.status,
    this.startDt,
    this.endDt,
    required this.notesJson,
    required this.continuityPhotoIdsJson,
    required this.updatedAt,
    required this.version,
    required this.cachedAt,
    required this.snapshotIndex,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['shooting_day_id'] = Variable<String>(shootingDayId);
    map['scene_id'] = Variable<String>(sceneId);
    map['planned_order'] = Variable<String>(plannedOrder);
    if (!nullToAbsent || actualOrder != null) {
      map['actual_order'] = Variable<String>(actualOrder);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || startDt != null) {
      map['start_dt'] = Variable<DateTime>(startDt);
    }
    if (!nullToAbsent || endDt != null) {
      map['end_dt'] = Variable<DateTime>(endDt);
    }
    map['notes_json'] = Variable<String>(notesJson);
    map['continuity_photo_ids_json'] = Variable<String>(continuityPhotoIdsJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['version'] = Variable<int>(version);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    map['snapshot_index'] = Variable<int>(snapshotIndex);
    return map;
  }

  SceneShootCacheRowsCompanion toCompanion(bool nullToAbsent) {
    return SceneShootCacheRowsCompanion(
      id: Value(id),
      shootingDayId: Value(shootingDayId),
      sceneId: Value(sceneId),
      plannedOrder: Value(plannedOrder),
      actualOrder: actualOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(actualOrder),
      status: Value(status),
      startDt: startDt == null && nullToAbsent
          ? const Value.absent()
          : Value(startDt),
      endDt: endDt == null && nullToAbsent
          ? const Value.absent()
          : Value(endDt),
      notesJson: Value(notesJson),
      continuityPhotoIdsJson: Value(continuityPhotoIdsJson),
      updatedAt: Value(updatedAt),
      version: Value(version),
      cachedAt: Value(cachedAt),
      snapshotIndex: Value(snapshotIndex),
    );
  }

  factory SceneShootCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SceneShootCacheRow(
      id: serializer.fromJson<String>(json['id']),
      shootingDayId: serializer.fromJson<String>(json['shootingDayId']),
      sceneId: serializer.fromJson<String>(json['sceneId']),
      plannedOrder: serializer.fromJson<String>(json['plannedOrder']),
      actualOrder: serializer.fromJson<String?>(json['actualOrder']),
      status: serializer.fromJson<String>(json['status']),
      startDt: serializer.fromJson<DateTime?>(json['startDt']),
      endDt: serializer.fromJson<DateTime?>(json['endDt']),
      notesJson: serializer.fromJson<String>(json['notesJson']),
      continuityPhotoIdsJson: serializer.fromJson<String>(
        json['continuityPhotoIdsJson'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      snapshotIndex: serializer.fromJson<int>(json['snapshotIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shootingDayId': serializer.toJson<String>(shootingDayId),
      'sceneId': serializer.toJson<String>(sceneId),
      'plannedOrder': serializer.toJson<String>(plannedOrder),
      'actualOrder': serializer.toJson<String?>(actualOrder),
      'status': serializer.toJson<String>(status),
      'startDt': serializer.toJson<DateTime?>(startDt),
      'endDt': serializer.toJson<DateTime?>(endDt),
      'notesJson': serializer.toJson<String>(notesJson),
      'continuityPhotoIdsJson': serializer.toJson<String>(
        continuityPhotoIdsJson,
      ),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'version': serializer.toJson<int>(version),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'snapshotIndex': serializer.toJson<int>(snapshotIndex),
    };
  }

  SceneShootCacheRow copyWith({
    String? id,
    String? shootingDayId,
    String? sceneId,
    String? plannedOrder,
    Value<String?> actualOrder = const Value.absent(),
    String? status,
    Value<DateTime?> startDt = const Value.absent(),
    Value<DateTime?> endDt = const Value.absent(),
    String? notesJson,
    String? continuityPhotoIdsJson,
    DateTime? updatedAt,
    int? version,
    DateTime? cachedAt,
    int? snapshotIndex,
  }) => SceneShootCacheRow(
    id: id ?? this.id,
    shootingDayId: shootingDayId ?? this.shootingDayId,
    sceneId: sceneId ?? this.sceneId,
    plannedOrder: plannedOrder ?? this.plannedOrder,
    actualOrder: actualOrder.present ? actualOrder.value : this.actualOrder,
    status: status ?? this.status,
    startDt: startDt.present ? startDt.value : this.startDt,
    endDt: endDt.present ? endDt.value : this.endDt,
    notesJson: notesJson ?? this.notesJson,
    continuityPhotoIdsJson:
        continuityPhotoIdsJson ?? this.continuityPhotoIdsJson,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
    cachedAt: cachedAt ?? this.cachedAt,
    snapshotIndex: snapshotIndex ?? this.snapshotIndex,
  );
  SceneShootCacheRow copyWithCompanion(SceneShootCacheRowsCompanion data) {
    return SceneShootCacheRow(
      id: data.id.present ? data.id.value : this.id,
      shootingDayId: data.shootingDayId.present
          ? data.shootingDayId.value
          : this.shootingDayId,
      sceneId: data.sceneId.present ? data.sceneId.value : this.sceneId,
      plannedOrder: data.plannedOrder.present
          ? data.plannedOrder.value
          : this.plannedOrder,
      actualOrder: data.actualOrder.present
          ? data.actualOrder.value
          : this.actualOrder,
      status: data.status.present ? data.status.value : this.status,
      startDt: data.startDt.present ? data.startDt.value : this.startDt,
      endDt: data.endDt.present ? data.endDt.value : this.endDt,
      notesJson: data.notesJson.present ? data.notesJson.value : this.notesJson,
      continuityPhotoIdsJson: data.continuityPhotoIdsJson.present
          ? data.continuityPhotoIdsJson.value
          : this.continuityPhotoIdsJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      snapshotIndex: data.snapshotIndex.present
          ? data.snapshotIndex.value
          : this.snapshotIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SceneShootCacheRow(')
          ..write('id: $id, ')
          ..write('shootingDayId: $shootingDayId, ')
          ..write('sceneId: $sceneId, ')
          ..write('plannedOrder: $plannedOrder, ')
          ..write('actualOrder: $actualOrder, ')
          ..write('status: $status, ')
          ..write('startDt: $startDt, ')
          ..write('endDt: $endDt, ')
          ..write('notesJson: $notesJson, ')
          ..write('continuityPhotoIdsJson: $continuityPhotoIdsJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('snapshotIndex: $snapshotIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    shootingDayId,
    sceneId,
    plannedOrder,
    actualOrder,
    status,
    startDt,
    endDt,
    notesJson,
    continuityPhotoIdsJson,
    updatedAt,
    version,
    cachedAt,
    snapshotIndex,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SceneShootCacheRow &&
          other.id == this.id &&
          other.shootingDayId == this.shootingDayId &&
          other.sceneId == this.sceneId &&
          other.plannedOrder == this.plannedOrder &&
          other.actualOrder == this.actualOrder &&
          other.status == this.status &&
          other.startDt == this.startDt &&
          other.endDt == this.endDt &&
          other.notesJson == this.notesJson &&
          other.continuityPhotoIdsJson == this.continuityPhotoIdsJson &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.cachedAt == this.cachedAt &&
          other.snapshotIndex == this.snapshotIndex);
}

class SceneShootCacheRowsCompanion extends UpdateCompanion<SceneShootCacheRow> {
  final Value<String> id;
  final Value<String> shootingDayId;
  final Value<String> sceneId;
  final Value<String> plannedOrder;
  final Value<String?> actualOrder;
  final Value<String> status;
  final Value<DateTime?> startDt;
  final Value<DateTime?> endDt;
  final Value<String> notesJson;
  final Value<String> continuityPhotoIdsJson;
  final Value<DateTime> updatedAt;
  final Value<int> version;
  final Value<DateTime> cachedAt;
  final Value<int> snapshotIndex;
  final Value<int> rowid;
  const SceneShootCacheRowsCompanion({
    this.id = const Value.absent(),
    this.shootingDayId = const Value.absent(),
    this.sceneId = const Value.absent(),
    this.plannedOrder = const Value.absent(),
    this.actualOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.startDt = const Value.absent(),
    this.endDt = const Value.absent(),
    this.notesJson = const Value.absent(),
    this.continuityPhotoIdsJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.snapshotIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SceneShootCacheRowsCompanion.insert({
    required String id,
    required String shootingDayId,
    required String sceneId,
    required String plannedOrder,
    this.actualOrder = const Value.absent(),
    required String status,
    this.startDt = const Value.absent(),
    this.endDt = const Value.absent(),
    required String notesJson,
    required String continuityPhotoIdsJson,
    required DateTime updatedAt,
    required int version,
    required DateTime cachedAt,
    required int snapshotIndex,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       shootingDayId = Value(shootingDayId),
       sceneId = Value(sceneId),
       plannedOrder = Value(plannedOrder),
       status = Value(status),
       notesJson = Value(notesJson),
       continuityPhotoIdsJson = Value(continuityPhotoIdsJson),
       updatedAt = Value(updatedAt),
       version = Value(version),
       cachedAt = Value(cachedAt),
       snapshotIndex = Value(snapshotIndex);
  static Insertable<SceneShootCacheRow> custom({
    Expression<String>? id,
    Expression<String>? shootingDayId,
    Expression<String>? sceneId,
    Expression<String>? plannedOrder,
    Expression<String>? actualOrder,
    Expression<String>? status,
    Expression<DateTime>? startDt,
    Expression<DateTime>? endDt,
    Expression<String>? notesJson,
    Expression<String>? continuityPhotoIdsJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? version,
    Expression<DateTime>? cachedAt,
    Expression<int>? snapshotIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shootingDayId != null) 'shooting_day_id': shootingDayId,
      if (sceneId != null) 'scene_id': sceneId,
      if (plannedOrder != null) 'planned_order': plannedOrder,
      if (actualOrder != null) 'actual_order': actualOrder,
      if (status != null) 'status': status,
      if (startDt != null) 'start_dt': startDt,
      if (endDt != null) 'end_dt': endDt,
      if (notesJson != null) 'notes_json': notesJson,
      if (continuityPhotoIdsJson != null)
        'continuity_photo_ids_json': continuityPhotoIdsJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (snapshotIndex != null) 'snapshot_index': snapshotIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SceneShootCacheRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? shootingDayId,
    Value<String>? sceneId,
    Value<String>? plannedOrder,
    Value<String?>? actualOrder,
    Value<String>? status,
    Value<DateTime?>? startDt,
    Value<DateTime?>? endDt,
    Value<String>? notesJson,
    Value<String>? continuityPhotoIdsJson,
    Value<DateTime>? updatedAt,
    Value<int>? version,
    Value<DateTime>? cachedAt,
    Value<int>? snapshotIndex,
    Value<int>? rowid,
  }) {
    return SceneShootCacheRowsCompanion(
      id: id ?? this.id,
      shootingDayId: shootingDayId ?? this.shootingDayId,
      sceneId: sceneId ?? this.sceneId,
      plannedOrder: plannedOrder ?? this.plannedOrder,
      actualOrder: actualOrder ?? this.actualOrder,
      status: status ?? this.status,
      startDt: startDt ?? this.startDt,
      endDt: endDt ?? this.endDt,
      notesJson: notesJson ?? this.notesJson,
      continuityPhotoIdsJson:
          continuityPhotoIdsJson ?? this.continuityPhotoIdsJson,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      cachedAt: cachedAt ?? this.cachedAt,
      snapshotIndex: snapshotIndex ?? this.snapshotIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shootingDayId.present) {
      map['shooting_day_id'] = Variable<String>(shootingDayId.value);
    }
    if (sceneId.present) {
      map['scene_id'] = Variable<String>(sceneId.value);
    }
    if (plannedOrder.present) {
      map['planned_order'] = Variable<String>(plannedOrder.value);
    }
    if (actualOrder.present) {
      map['actual_order'] = Variable<String>(actualOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startDt.present) {
      map['start_dt'] = Variable<DateTime>(startDt.value);
    }
    if (endDt.present) {
      map['end_dt'] = Variable<DateTime>(endDt.value);
    }
    if (notesJson.present) {
      map['notes_json'] = Variable<String>(notesJson.value);
    }
    if (continuityPhotoIdsJson.present) {
      map['continuity_photo_ids_json'] = Variable<String>(
        continuityPhotoIdsJson.value,
      );
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
    if (snapshotIndex.present) {
      map['snapshot_index'] = Variable<int>(snapshotIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SceneShootCacheRowsCompanion(')
          ..write('id: $id, ')
          ..write('shootingDayId: $shootingDayId, ')
          ..write('sceneId: $sceneId, ')
          ..write('plannedOrder: $plannedOrder, ')
          ..write('actualOrder: $actualOrder, ')
          ..write('status: $status, ')
          ..write('startDt: $startDt, ')
          ..write('endDt: $endDt, ')
          ..write('notesJson: $notesJson, ')
          ..write('continuityPhotoIdsJson: $continuityPhotoIdsJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('snapshotIndex: $snapshotIndex, ')
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
  late final $BlockCacheRowsTable blockCacheRows = $BlockCacheRowsTable(this);
  late final $EpisodeCacheRowsTable episodeCacheRows = $EpisodeCacheRowsTable(
    this,
  );
  late final $SceneCacheRowsTable sceneCacheRows = $SceneCacheRowsTable(this);
  late final $CostumeCategoryCacheRowsTable costumeCategoryCacheRows =
      $CostumeCategoryCacheRowsTable(this);
  late final $CostumeCacheRowsTable costumeCacheRows = $CostumeCacheRowsTable(
    this,
  );
  late final $CharacterCacheRowsTable characterCacheRows =
      $CharacterCacheRowsTable(this);
  late final $ShootingDayCacheRowsTable shootingDayCacheRows =
      $ShootingDayCacheRowsTable(this);
  late final $SceneShootCacheRowsTable sceneShootCacheRows =
      $SceneShootCacheRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    seasonCacheRows,
    blockCacheRows,
    episodeCacheRows,
    sceneCacheRows,
    costumeCategoryCacheRows,
    costumeCacheRows,
    characterCacheRows,
    shootingDayCacheRows,
    sceneShootCacheRows,
  ];
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
typedef $$BlockCacheRowsTableCreateCompanionBuilder =
    BlockCacheRowsCompanion Function({
      required String id,
      required int number,
      required String seasonId,
      required String seriesId,
      required String startDate,
      required String endDate,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$BlockCacheRowsTableUpdateCompanionBuilder =
    BlockCacheRowsCompanion Function({
      Value<String> id,
      Value<int> number,
      Value<String> seasonId,
      Value<String> seriesId,
      Value<String> startDate,
      Value<String> endDate,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$BlockCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $BlockCacheRowsTable> {
  $$BlockCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
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

class $$BlockCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $BlockCacheRowsTable> {
  $$BlockCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
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

class $$BlockCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $BlockCacheRowsTable> {
  $$BlockCacheRowsTableAnnotationComposer({
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

  GeneratedColumn<String> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$BlockCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $BlockCacheRowsTable,
          BlockCacheRow,
          $$BlockCacheRowsTableFilterComposer,
          $$BlockCacheRowsTableOrderingComposer,
          $$BlockCacheRowsTableAnnotationComposer,
          $$BlockCacheRowsTableCreateCompanionBuilder,
          $$BlockCacheRowsTableUpdateCompanionBuilder,
          (
            BlockCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $BlockCacheRowsTable,
              BlockCacheRow
            >,
          ),
          BlockCacheRow,
          PrefetchHooks Function()
        > {
  $$BlockCacheRowsTableTableManager(
    _$CacheDatabase db,
    $BlockCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> seasonId = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String> endDate = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockCacheRowsCompanion(
                id: id,
                number: number,
                seasonId: seasonId,
                seriesId: seriesId,
                startDate: startDate,
                endDate: endDate,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int number,
                required String seasonId,
                required String seriesId,
                required String startDate,
                required String endDate,
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => BlockCacheRowsCompanion.insert(
                id: id,
                number: number,
                seasonId: seasonId,
                seriesId: seriesId,
                startDate: startDate,
                endDate: endDate,
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

typedef $$BlockCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $BlockCacheRowsTable,
      BlockCacheRow,
      $$BlockCacheRowsTableFilterComposer,
      $$BlockCacheRowsTableOrderingComposer,
      $$BlockCacheRowsTableAnnotationComposer,
      $$BlockCacheRowsTableCreateCompanionBuilder,
      $$BlockCacheRowsTableUpdateCompanionBuilder,
      (
        BlockCacheRow,
        BaseReferences<_$CacheDatabase, $BlockCacheRowsTable, BlockCacheRow>,
      ),
      BlockCacheRow,
      PrefetchHooks Function()
    >;
typedef $$EpisodeCacheRowsTableCreateCompanionBuilder =
    EpisodeCacheRowsCompanion Function({
      required String id,
      required String blockId,
      Value<String?> name,
      required int number,
      required String seriesId,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$EpisodeCacheRowsTableUpdateCompanionBuilder =
    EpisodeCacheRowsCompanion Function({
      Value<String> id,
      Value<String> blockId,
      Value<String?> name,
      Value<int> number,
      Value<String> seriesId,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$EpisodeCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $EpisodeCacheRowsTable> {
  $$EpisodeCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
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

class $$EpisodeCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $EpisodeCacheRowsTable> {
  $$EpisodeCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
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

class $$EpisodeCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $EpisodeCacheRowsTable> {
  $$EpisodeCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get blockId =>
      $composableBuilder(column: $table.blockId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$EpisodeCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $EpisodeCacheRowsTable,
          EpisodeCacheRow,
          $$EpisodeCacheRowsTableFilterComposer,
          $$EpisodeCacheRowsTableOrderingComposer,
          $$EpisodeCacheRowsTableAnnotationComposer,
          $$EpisodeCacheRowsTableCreateCompanionBuilder,
          $$EpisodeCacheRowsTableUpdateCompanionBuilder,
          (
            EpisodeCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $EpisodeCacheRowsTable,
              EpisodeCacheRow
            >,
          ),
          EpisodeCacheRow,
          PrefetchHooks Function()
        > {
  $$EpisodeCacheRowsTableTableManager(
    _$CacheDatabase db,
    $EpisodeCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodeCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodeCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodeCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> blockId = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodeCacheRowsCompanion(
                id: id,
                blockId: blockId,
                name: name,
                number: number,
                seriesId: seriesId,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String blockId,
                Value<String?> name = const Value.absent(),
                required int number,
                required String seriesId,
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => EpisodeCacheRowsCompanion.insert(
                id: id,
                blockId: blockId,
                name: name,
                number: number,
                seriesId: seriesId,
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

typedef $$EpisodeCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $EpisodeCacheRowsTable,
      EpisodeCacheRow,
      $$EpisodeCacheRowsTableFilterComposer,
      $$EpisodeCacheRowsTableOrderingComposer,
      $$EpisodeCacheRowsTableAnnotationComposer,
      $$EpisodeCacheRowsTableCreateCompanionBuilder,
      $$EpisodeCacheRowsTableUpdateCompanionBuilder,
      (
        EpisodeCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $EpisodeCacheRowsTable,
          EpisodeCacheRow
        >,
      ),
      EpisodeCacheRow,
      PrefetchHooks Function()
    >;
typedef $$SceneCacheRowsTableCreateCompanionBuilder =
    SceneCacheRowsCompanion Function({
      required String id,
      required String episodeId,
      required String assignedCharacters,
      required bool isScheduleSet,
      Value<String?> location,
      Value<String?> mood,
      Value<int?> sceneNumber,
      Value<String?> scriptDay,
      required String shootingDayIds,
      Value<String?> summary,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$SceneCacheRowsTableUpdateCompanionBuilder =
    SceneCacheRowsCompanion Function({
      Value<String> id,
      Value<String> episodeId,
      Value<String> assignedCharacters,
      Value<bool> isScheduleSet,
      Value<String?> location,
      Value<String?> mood,
      Value<int?> sceneNumber,
      Value<String?> scriptDay,
      Value<String> shootingDayIds,
      Value<String?> summary,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$SceneCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $SceneCacheRowsTable> {
  $$SceneCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedCharacters => $composableBuilder(
    column: $table.assignedCharacters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isScheduleSet => $composableBuilder(
    column: $table.isScheduleSet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sceneNumber => $composableBuilder(
    column: $table.sceneNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scriptDay => $composableBuilder(
    column: $table.scriptDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shootingDayIds => $composableBuilder(
    column: $table.shootingDayIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
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

class $$SceneCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $SceneCacheRowsTable> {
  $$SceneCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedCharacters => $composableBuilder(
    column: $table.assignedCharacters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isScheduleSet => $composableBuilder(
    column: $table.isScheduleSet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sceneNumber => $composableBuilder(
    column: $table.sceneNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scriptDay => $composableBuilder(
    column: $table.scriptDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shootingDayIds => $composableBuilder(
    column: $table.shootingDayIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
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

class $$SceneCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SceneCacheRowsTable> {
  $$SceneCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<String> get assignedCharacters => $composableBuilder(
    column: $table.assignedCharacters,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isScheduleSet => $composableBuilder(
    column: $table.isScheduleSet,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<int> get sceneNumber => $composableBuilder(
    column: $table.sceneNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scriptDay =>
      $composableBuilder(column: $table.scriptDay, builder: (column) => column);

  GeneratedColumn<String> get shootingDayIds => $composableBuilder(
    column: $table.shootingDayIds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$SceneCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SceneCacheRowsTable,
          SceneCacheRow,
          $$SceneCacheRowsTableFilterComposer,
          $$SceneCacheRowsTableOrderingComposer,
          $$SceneCacheRowsTableAnnotationComposer,
          $$SceneCacheRowsTableCreateCompanionBuilder,
          $$SceneCacheRowsTableUpdateCompanionBuilder,
          (
            SceneCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $SceneCacheRowsTable,
              SceneCacheRow
            >,
          ),
          SceneCacheRow,
          PrefetchHooks Function()
        > {
  $$SceneCacheRowsTableTableManager(
    _$CacheDatabase db,
    $SceneCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SceneCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SceneCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SceneCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> episodeId = const Value.absent(),
                Value<String> assignedCharacters = const Value.absent(),
                Value<bool> isScheduleSet = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<int?> sceneNumber = const Value.absent(),
                Value<String?> scriptDay = const Value.absent(),
                Value<String> shootingDayIds = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SceneCacheRowsCompanion(
                id: id,
                episodeId: episodeId,
                assignedCharacters: assignedCharacters,
                isScheduleSet: isScheduleSet,
                location: location,
                mood: mood,
                sceneNumber: sceneNumber,
                scriptDay: scriptDay,
                shootingDayIds: shootingDayIds,
                summary: summary,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String episodeId,
                required String assignedCharacters,
                required bool isScheduleSet,
                Value<String?> location = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<int?> sceneNumber = const Value.absent(),
                Value<String?> scriptDay = const Value.absent(),
                required String shootingDayIds,
                Value<String?> summary = const Value.absent(),
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => SceneCacheRowsCompanion.insert(
                id: id,
                episodeId: episodeId,
                assignedCharacters: assignedCharacters,
                isScheduleSet: isScheduleSet,
                location: location,
                mood: mood,
                sceneNumber: sceneNumber,
                scriptDay: scriptDay,
                shootingDayIds: shootingDayIds,
                summary: summary,
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

typedef $$SceneCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SceneCacheRowsTable,
      SceneCacheRow,
      $$SceneCacheRowsTableFilterComposer,
      $$SceneCacheRowsTableOrderingComposer,
      $$SceneCacheRowsTableAnnotationComposer,
      $$SceneCacheRowsTableCreateCompanionBuilder,
      $$SceneCacheRowsTableUpdateCompanionBuilder,
      (
        SceneCacheRow,
        BaseReferences<_$CacheDatabase, $SceneCacheRowsTable, SceneCacheRow>,
      ),
      SceneCacheRow,
      PrefetchHooks Function()
    >;
typedef $$CostumeCategoryCacheRowsTableCreateCompanionBuilder =
    CostumeCategoryCacheRowsCompanion Function({
      required String id,
      required String seasonId,
      required String name,
      required String orderKey,
      required bool archived,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CostumeCategoryCacheRowsTableUpdateCompanionBuilder =
    CostumeCategoryCacheRowsCompanion Function({
      Value<String> id,
      Value<String> seasonId,
      Value<String> name,
      Value<String> orderKey,
      Value<bool> archived,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CostumeCategoryCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $CostumeCategoryCacheRowsTable> {
  $$CostumeCategoryCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderKey => $composableBuilder(
    column: $table.orderKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
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

class $$CostumeCategoryCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CostumeCategoryCacheRowsTable> {
  $$CostumeCategoryCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderKey => $composableBuilder(
    column: $table.orderKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
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

class $$CostumeCategoryCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CostumeCategoryCacheRowsTable> {
  $$CostumeCategoryCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get orderKey =>
      $composableBuilder(column: $table.orderKey, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CostumeCategoryCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CostumeCategoryCacheRowsTable,
          CostumeCategoryCacheRow,
          $$CostumeCategoryCacheRowsTableFilterComposer,
          $$CostumeCategoryCacheRowsTableOrderingComposer,
          $$CostumeCategoryCacheRowsTableAnnotationComposer,
          $$CostumeCategoryCacheRowsTableCreateCompanionBuilder,
          $$CostumeCategoryCacheRowsTableUpdateCompanionBuilder,
          (
            CostumeCategoryCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $CostumeCategoryCacheRowsTable,
              CostumeCategoryCacheRow
            >,
          ),
          CostumeCategoryCacheRow,
          PrefetchHooks Function()
        > {
  $$CostumeCategoryCacheRowsTableTableManager(
    _$CacheDatabase db,
    $CostumeCategoryCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CostumeCategoryCacheRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CostumeCategoryCacheRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CostumeCategoryCacheRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> seasonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> orderKey = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CostumeCategoryCacheRowsCompanion(
                id: id,
                seasonId: seasonId,
                name: name,
                orderKey: orderKey,
                archived: archived,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String seasonId,
                required String name,
                required String orderKey,
                required bool archived,
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CostumeCategoryCacheRowsCompanion.insert(
                id: id,
                seasonId: seasonId,
                name: name,
                orderKey: orderKey,
                archived: archived,
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

typedef $$CostumeCategoryCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CostumeCategoryCacheRowsTable,
      CostumeCategoryCacheRow,
      $$CostumeCategoryCacheRowsTableFilterComposer,
      $$CostumeCategoryCacheRowsTableOrderingComposer,
      $$CostumeCategoryCacheRowsTableAnnotationComposer,
      $$CostumeCategoryCacheRowsTableCreateCompanionBuilder,
      $$CostumeCategoryCacheRowsTableUpdateCompanionBuilder,
      (
        CostumeCategoryCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $CostumeCategoryCacheRowsTable,
          CostumeCategoryCacheRow
        >,
      ),
      CostumeCategoryCacheRow,
      PrefetchHooks Function()
    >;
typedef $$CostumeCacheRowsTableCreateCompanionBuilder =
    CostumeCacheRowsCompanion Function({
      required String id,
      required String seasonId,
      Value<String?> characterId,
      required String notes,
      required String detailsJson,
      required String photosJson,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      required int snapshotIndex,
      Value<int> rowid,
    });
typedef $$CostumeCacheRowsTableUpdateCompanionBuilder =
    CostumeCacheRowsCompanion Function({
      Value<String> id,
      Value<String> seasonId,
      Value<String?> characterId,
      Value<String> notes,
      Value<String> detailsJson,
      Value<String> photosJson,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> snapshotIndex,
      Value<int> rowid,
    });

class $$CostumeCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $CostumeCacheRowsTable> {
  $$CostumeCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photosJson => $composableBuilder(
    column: $table.photosJson,
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

  ColumnFilters<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CostumeCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CostumeCacheRowsTable> {
  $$CostumeCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photosJson => $composableBuilder(
    column: $table.photosJson,
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

  ColumnOrderings<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CostumeCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CostumeCacheRowsTable> {
  $$CostumeCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photosJson => $composableBuilder(
    column: $table.photosJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => column,
  );
}

class $$CostumeCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CostumeCacheRowsTable,
          CostumeCacheRow,
          $$CostumeCacheRowsTableFilterComposer,
          $$CostumeCacheRowsTableOrderingComposer,
          $$CostumeCacheRowsTableAnnotationComposer,
          $$CostumeCacheRowsTableCreateCompanionBuilder,
          $$CostumeCacheRowsTableUpdateCompanionBuilder,
          (
            CostumeCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $CostumeCacheRowsTable,
              CostumeCacheRow
            >,
          ),
          CostumeCacheRow,
          PrefetchHooks Function()
        > {
  $$CostumeCacheRowsTableTableManager(
    _$CacheDatabase db,
    $CostumeCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CostumeCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CostumeCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CostumeCacheRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> seasonId = const Value.absent(),
                Value<String?> characterId = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<String> photosJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> snapshotIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CostumeCacheRowsCompanion(
                id: id,
                seasonId: seasonId,
                characterId: characterId,
                notes: notes,
                detailsJson: detailsJson,
                photosJson: photosJson,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                snapshotIndex: snapshotIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String seasonId,
                Value<String?> characterId = const Value.absent(),
                required String notes,
                required String detailsJson,
                required String photosJson,
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                required int snapshotIndex,
                Value<int> rowid = const Value.absent(),
              }) => CostumeCacheRowsCompanion.insert(
                id: id,
                seasonId: seasonId,
                characterId: characterId,
                notes: notes,
                detailsJson: detailsJson,
                photosJson: photosJson,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                snapshotIndex: snapshotIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CostumeCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CostumeCacheRowsTable,
      CostumeCacheRow,
      $$CostumeCacheRowsTableFilterComposer,
      $$CostumeCacheRowsTableOrderingComposer,
      $$CostumeCacheRowsTableAnnotationComposer,
      $$CostumeCacheRowsTableCreateCompanionBuilder,
      $$CostumeCacheRowsTableUpdateCompanionBuilder,
      (
        CostumeCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $CostumeCacheRowsTable,
          CostumeCacheRow
        >,
      ),
      CostumeCacheRow,
      PrefetchHooks Function()
    >;
typedef $$CharacterCacheRowsTableCreateCompanionBuilder =
    CharacterCacheRowsCompanion Function({
      required String id,
      required String seasonId,
      required String name,
      required String category,
      required String height,
      required String weight,
      required String chest,
      required String waist,
      required String hips,
      required String shoeSize,
      required String hatSize,
      Value<String?> email,
      Value<String?> phone,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CharacterCacheRowsTableUpdateCompanionBuilder =
    CharacterCacheRowsCompanion Function({
      Value<String> id,
      Value<String> seasonId,
      Value<String> name,
      Value<String> category,
      Value<String> height,
      Value<String> weight,
      Value<String> chest,
      Value<String> waist,
      Value<String> hips,
      Value<String> shoeSize,
      Value<String> hatSize,
      Value<String?> email,
      Value<String?> phone,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CharacterCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $CharacterCacheRowsTable> {
  $$CharacterCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chest => $composableBuilder(
    column: $table.chest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get waist => $composableBuilder(
    column: $table.waist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hips => $composableBuilder(
    column: $table.hips,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shoeSize => $composableBuilder(
    column: $table.shoeSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hatSize => $composableBuilder(
    column: $table.hatSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
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

class $$CharacterCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $CharacterCacheRowsTable> {
  $$CharacterCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chest => $composableBuilder(
    column: $table.chest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get waist => $composableBuilder(
    column: $table.waist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hips => $composableBuilder(
    column: $table.hips,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shoeSize => $composableBuilder(
    column: $table.shoeSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hatSize => $composableBuilder(
    column: $table.hatSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
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

class $$CharacterCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CharacterCacheRowsTable> {
  $$CharacterCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<String> get chest =>
      $composableBuilder(column: $table.chest, builder: (column) => column);

  GeneratedColumn<String> get waist =>
      $composableBuilder(column: $table.waist, builder: (column) => column);

  GeneratedColumn<String> get hips =>
      $composableBuilder(column: $table.hips, builder: (column) => column);

  GeneratedColumn<String> get shoeSize =>
      $composableBuilder(column: $table.shoeSize, builder: (column) => column);

  GeneratedColumn<String> get hatSize =>
      $composableBuilder(column: $table.hatSize, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CharacterCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CharacterCacheRowsTable,
          CharacterCacheRow,
          $$CharacterCacheRowsTableFilterComposer,
          $$CharacterCacheRowsTableOrderingComposer,
          $$CharacterCacheRowsTableAnnotationComposer,
          $$CharacterCacheRowsTableCreateCompanionBuilder,
          $$CharacterCacheRowsTableUpdateCompanionBuilder,
          (
            CharacterCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $CharacterCacheRowsTable,
              CharacterCacheRow
            >,
          ),
          CharacterCacheRow,
          PrefetchHooks Function()
        > {
  $$CharacterCacheRowsTableTableManager(
    _$CacheDatabase db,
    $CharacterCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterCacheRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharacterCacheRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> seasonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> height = const Value.absent(),
                Value<String> weight = const Value.absent(),
                Value<String> chest = const Value.absent(),
                Value<String> waist = const Value.absent(),
                Value<String> hips = const Value.absent(),
                Value<String> shoeSize = const Value.absent(),
                Value<String> hatSize = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharacterCacheRowsCompanion(
                id: id,
                seasonId: seasonId,
                name: name,
                category: category,
                height: height,
                weight: weight,
                chest: chest,
                waist: waist,
                hips: hips,
                shoeSize: shoeSize,
                hatSize: hatSize,
                email: email,
                phone: phone,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String seasonId,
                required String name,
                required String category,
                required String height,
                required String weight,
                required String chest,
                required String waist,
                required String hips,
                required String shoeSize,
                required String hatSize,
                Value<String?> email = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CharacterCacheRowsCompanion.insert(
                id: id,
                seasonId: seasonId,
                name: name,
                category: category,
                height: height,
                weight: weight,
                chest: chest,
                waist: waist,
                hips: hips,
                shoeSize: shoeSize,
                hatSize: hatSize,
                email: email,
                phone: phone,
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

typedef $$CharacterCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CharacterCacheRowsTable,
      CharacterCacheRow,
      $$CharacterCacheRowsTableFilterComposer,
      $$CharacterCacheRowsTableOrderingComposer,
      $$CharacterCacheRowsTableAnnotationComposer,
      $$CharacterCacheRowsTableCreateCompanionBuilder,
      $$CharacterCacheRowsTableUpdateCompanionBuilder,
      (
        CharacterCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $CharacterCacheRowsTable,
          CharacterCacheRow
        >,
      ),
      CharacterCacheRow,
      PrefetchHooks Function()
    >;
typedef $$ShootingDayCacheRowsTableCreateCompanionBuilder =
    ShootingDayCacheRowsCompanion Function({
      required String id,
      required String episodeId,
      required String orderKey,
      required String sourceJson,
      Value<String?> label,
      Value<String?> date,
      required bool archived,
      Value<DateTime?> wrappedAt,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$ShootingDayCacheRowsTableUpdateCompanionBuilder =
    ShootingDayCacheRowsCompanion Function({
      Value<String> id,
      Value<String> episodeId,
      Value<String> orderKey,
      Value<String> sourceJson,
      Value<String?> label,
      Value<String?> date,
      Value<bool> archived,
      Value<DateTime?> wrappedAt,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$ShootingDayCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $ShootingDayCacheRowsTable> {
  $$ShootingDayCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderKey => $composableBuilder(
    column: $table.orderKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get wrappedAt => $composableBuilder(
    column: $table.wrappedAt,
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

class $$ShootingDayCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $ShootingDayCacheRowsTable> {
  $$ShootingDayCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get episodeId => $composableBuilder(
    column: $table.episodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderKey => $composableBuilder(
    column: $table.orderKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get wrappedAt => $composableBuilder(
    column: $table.wrappedAt,
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

class $$ShootingDayCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $ShootingDayCacheRowsTable> {
  $$ShootingDayCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get episodeId =>
      $composableBuilder(column: $table.episodeId, builder: (column) => column);

  GeneratedColumn<String> get orderKey =>
      $composableBuilder(column: $table.orderKey, builder: (column) => column);

  GeneratedColumn<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<DateTime> get wrappedAt =>
      $composableBuilder(column: $table.wrappedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$ShootingDayCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $ShootingDayCacheRowsTable,
          ShootingDayCacheRow,
          $$ShootingDayCacheRowsTableFilterComposer,
          $$ShootingDayCacheRowsTableOrderingComposer,
          $$ShootingDayCacheRowsTableAnnotationComposer,
          $$ShootingDayCacheRowsTableCreateCompanionBuilder,
          $$ShootingDayCacheRowsTableUpdateCompanionBuilder,
          (
            ShootingDayCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $ShootingDayCacheRowsTable,
              ShootingDayCacheRow
            >,
          ),
          ShootingDayCacheRow,
          PrefetchHooks Function()
        > {
  $$ShootingDayCacheRowsTableTableManager(
    _$CacheDatabase db,
    $ShootingDayCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShootingDayCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShootingDayCacheRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ShootingDayCacheRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> episodeId = const Value.absent(),
                Value<String> orderKey = const Value.absent(),
                Value<String> sourceJson = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String?> date = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<DateTime?> wrappedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShootingDayCacheRowsCompanion(
                id: id,
                episodeId: episodeId,
                orderKey: orderKey,
                sourceJson: sourceJson,
                label: label,
                date: date,
                archived: archived,
                wrappedAt: wrappedAt,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String episodeId,
                required String orderKey,
                required String sourceJson,
                Value<String?> label = const Value.absent(),
                Value<String?> date = const Value.absent(),
                required bool archived,
                Value<DateTime?> wrappedAt = const Value.absent(),
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => ShootingDayCacheRowsCompanion.insert(
                id: id,
                episodeId: episodeId,
                orderKey: orderKey,
                sourceJson: sourceJson,
                label: label,
                date: date,
                archived: archived,
                wrappedAt: wrappedAt,
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

typedef $$ShootingDayCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $ShootingDayCacheRowsTable,
      ShootingDayCacheRow,
      $$ShootingDayCacheRowsTableFilterComposer,
      $$ShootingDayCacheRowsTableOrderingComposer,
      $$ShootingDayCacheRowsTableAnnotationComposer,
      $$ShootingDayCacheRowsTableCreateCompanionBuilder,
      $$ShootingDayCacheRowsTableUpdateCompanionBuilder,
      (
        ShootingDayCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $ShootingDayCacheRowsTable,
          ShootingDayCacheRow
        >,
      ),
      ShootingDayCacheRow,
      PrefetchHooks Function()
    >;
typedef $$SceneShootCacheRowsTableCreateCompanionBuilder =
    SceneShootCacheRowsCompanion Function({
      required String id,
      required String shootingDayId,
      required String sceneId,
      required String plannedOrder,
      Value<String?> actualOrder,
      required String status,
      Value<DateTime?> startDt,
      Value<DateTime?> endDt,
      required String notesJson,
      required String continuityPhotoIdsJson,
      required DateTime updatedAt,
      required int version,
      required DateTime cachedAt,
      required int snapshotIndex,
      Value<int> rowid,
    });
typedef $$SceneShootCacheRowsTableUpdateCompanionBuilder =
    SceneShootCacheRowsCompanion Function({
      Value<String> id,
      Value<String> shootingDayId,
      Value<String> sceneId,
      Value<String> plannedOrder,
      Value<String?> actualOrder,
      Value<String> status,
      Value<DateTime?> startDt,
      Value<DateTime?> endDt,
      Value<String> notesJson,
      Value<String> continuityPhotoIdsJson,
      Value<DateTime> updatedAt,
      Value<int> version,
      Value<DateTime> cachedAt,
      Value<int> snapshotIndex,
      Value<int> rowid,
    });

class $$SceneShootCacheRowsTableFilterComposer
    extends Composer<_$CacheDatabase, $SceneShootCacheRowsTable> {
  $$SceneShootCacheRowsTableFilterComposer({
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

  ColumnFilters<String> get shootingDayId => $composableBuilder(
    column: $table.shootingDayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sceneId => $composableBuilder(
    column: $table.sceneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plannedOrder => $composableBuilder(
    column: $table.plannedOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actualOrder => $composableBuilder(
    column: $table.actualOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDt => $composableBuilder(
    column: $table.startDt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDt => $composableBuilder(
    column: $table.endDt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notesJson => $composableBuilder(
    column: $table.notesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get continuityPhotoIdsJson => $composableBuilder(
    column: $table.continuityPhotoIdsJson,
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

  ColumnFilters<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SceneShootCacheRowsTableOrderingComposer
    extends Composer<_$CacheDatabase, $SceneShootCacheRowsTable> {
  $$SceneShootCacheRowsTableOrderingComposer({
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

  ColumnOrderings<String> get shootingDayId => $composableBuilder(
    column: $table.shootingDayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sceneId => $composableBuilder(
    column: $table.sceneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plannedOrder => $composableBuilder(
    column: $table.plannedOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actualOrder => $composableBuilder(
    column: $table.actualOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDt => $composableBuilder(
    column: $table.startDt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDt => $composableBuilder(
    column: $table.endDt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notesJson => $composableBuilder(
    column: $table.notesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get continuityPhotoIdsJson => $composableBuilder(
    column: $table.continuityPhotoIdsJson,
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

  ColumnOrderings<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SceneShootCacheRowsTableAnnotationComposer
    extends Composer<_$CacheDatabase, $SceneShootCacheRowsTable> {
  $$SceneShootCacheRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get shootingDayId => $composableBuilder(
    column: $table.shootingDayId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sceneId =>
      $composableBuilder(column: $table.sceneId, builder: (column) => column);

  GeneratedColumn<String> get plannedOrder => $composableBuilder(
    column: $table.plannedOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actualOrder => $composableBuilder(
    column: $table.actualOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startDt =>
      $composableBuilder(column: $table.startDt, builder: (column) => column);

  GeneratedColumn<DateTime> get endDt =>
      $composableBuilder(column: $table.endDt, builder: (column) => column);

  GeneratedColumn<String> get notesJson =>
      $composableBuilder(column: $table.notesJson, builder: (column) => column);

  GeneratedColumn<String> get continuityPhotoIdsJson => $composableBuilder(
    column: $table.continuityPhotoIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<int> get snapshotIndex => $composableBuilder(
    column: $table.snapshotIndex,
    builder: (column) => column,
  );
}

class $$SceneShootCacheRowsTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $SceneShootCacheRowsTable,
          SceneShootCacheRow,
          $$SceneShootCacheRowsTableFilterComposer,
          $$SceneShootCacheRowsTableOrderingComposer,
          $$SceneShootCacheRowsTableAnnotationComposer,
          $$SceneShootCacheRowsTableCreateCompanionBuilder,
          $$SceneShootCacheRowsTableUpdateCompanionBuilder,
          (
            SceneShootCacheRow,
            BaseReferences<
              _$CacheDatabase,
              $SceneShootCacheRowsTable,
              SceneShootCacheRow
            >,
          ),
          SceneShootCacheRow,
          PrefetchHooks Function()
        > {
  $$SceneShootCacheRowsTableTableManager(
    _$CacheDatabase db,
    $SceneShootCacheRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SceneShootCacheRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SceneShootCacheRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SceneShootCacheRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shootingDayId = const Value.absent(),
                Value<String> sceneId = const Value.absent(),
                Value<String> plannedOrder = const Value.absent(),
                Value<String?> actualOrder = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> startDt = const Value.absent(),
                Value<DateTime?> endDt = const Value.absent(),
                Value<String> notesJson = const Value.absent(),
                Value<String> continuityPhotoIdsJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> snapshotIndex = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SceneShootCacheRowsCompanion(
                id: id,
                shootingDayId: shootingDayId,
                sceneId: sceneId,
                plannedOrder: plannedOrder,
                actualOrder: actualOrder,
                status: status,
                startDt: startDt,
                endDt: endDt,
                notesJson: notesJson,
                continuityPhotoIdsJson: continuityPhotoIdsJson,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                snapshotIndex: snapshotIndex,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String shootingDayId,
                required String sceneId,
                required String plannedOrder,
                Value<String?> actualOrder = const Value.absent(),
                required String status,
                Value<DateTime?> startDt = const Value.absent(),
                Value<DateTime?> endDt = const Value.absent(),
                required String notesJson,
                required String continuityPhotoIdsJson,
                required DateTime updatedAt,
                required int version,
                required DateTime cachedAt,
                required int snapshotIndex,
                Value<int> rowid = const Value.absent(),
              }) => SceneShootCacheRowsCompanion.insert(
                id: id,
                shootingDayId: shootingDayId,
                sceneId: sceneId,
                plannedOrder: plannedOrder,
                actualOrder: actualOrder,
                status: status,
                startDt: startDt,
                endDt: endDt,
                notesJson: notesJson,
                continuityPhotoIdsJson: continuityPhotoIdsJson,
                updatedAt: updatedAt,
                version: version,
                cachedAt: cachedAt,
                snapshotIndex: snapshotIndex,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SceneShootCacheRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $SceneShootCacheRowsTable,
      SceneShootCacheRow,
      $$SceneShootCacheRowsTableFilterComposer,
      $$SceneShootCacheRowsTableOrderingComposer,
      $$SceneShootCacheRowsTableAnnotationComposer,
      $$SceneShootCacheRowsTableCreateCompanionBuilder,
      $$SceneShootCacheRowsTableUpdateCompanionBuilder,
      (
        SceneShootCacheRow,
        BaseReferences<
          _$CacheDatabase,
          $SceneShootCacheRowsTable,
          SceneShootCacheRow
        >,
      ),
      SceneShootCacheRow,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$SeasonCacheRowsTableTableManager get seasonCacheRows =>
      $$SeasonCacheRowsTableTableManager(_db, _db.seasonCacheRows);
  $$BlockCacheRowsTableTableManager get blockCacheRows =>
      $$BlockCacheRowsTableTableManager(_db, _db.blockCacheRows);
  $$EpisodeCacheRowsTableTableManager get episodeCacheRows =>
      $$EpisodeCacheRowsTableTableManager(_db, _db.episodeCacheRows);
  $$SceneCacheRowsTableTableManager get sceneCacheRows =>
      $$SceneCacheRowsTableTableManager(_db, _db.sceneCacheRows);
  $$CostumeCategoryCacheRowsTableTableManager get costumeCategoryCacheRows =>
      $$CostumeCategoryCacheRowsTableTableManager(
        _db,
        _db.costumeCategoryCacheRows,
      );
  $$CostumeCacheRowsTableTableManager get costumeCacheRows =>
      $$CostumeCacheRowsTableTableManager(_db, _db.costumeCacheRows);
  $$CharacterCacheRowsTableTableManager get characterCacheRows =>
      $$CharacterCacheRowsTableTableManager(_db, _db.characterCacheRows);
  $$ShootingDayCacheRowsTableTableManager get shootingDayCacheRows =>
      $$ShootingDayCacheRowsTableTableManager(_db, _db.shootingDayCacheRows);
  $$SceneShootCacheRowsTableTableManager get sceneShootCacheRows =>
      $$SceneShootCacheRowsTableTableManager(_db, _db.sceneShootCacheRows);
}
