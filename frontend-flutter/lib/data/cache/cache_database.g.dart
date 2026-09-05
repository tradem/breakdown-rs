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
}
