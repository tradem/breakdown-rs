// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'probe_scene_rows_v8.dart';

// ignore_for_file: type=lint
class $ProbeSceneRowsV8Table extends ProbeSceneRowsV8
    with TableInfo<$ProbeSceneRowsV8Table, ProbeSceneRowsV8Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProbeSceneRowsV8Table(this.attachedDatabase, [this._alias]);
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
    Insertable<ProbeSceneRowsV8Data> instance, {
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
  ProbeSceneRowsV8Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProbeSceneRowsV8Data(
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
  $ProbeSceneRowsV8Table createAlias(String alias) {
    return $ProbeSceneRowsV8Table(attachedDatabase, alias);
  }
}

class ProbeSceneRowsV8Data extends DataClass
    implements Insertable<ProbeSceneRowsV8Data> {
  final String id;
  final String episodeId;
  final String assignedCharacters;
  final bool isScheduleSet;
  final String? location;
  final String? mood;
  final int? sceneNumber;
  final String? scriptDay;
  final String shootingDayIds;
  final String? summary;
  final DateTime updatedAt;
  final int version;
  final DateTime cachedAt;
  const ProbeSceneRowsV8Data({
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

  ProbeSceneRowsV8Companion toCompanion(bool nullToAbsent) {
    return ProbeSceneRowsV8Companion(
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

  factory ProbeSceneRowsV8Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProbeSceneRowsV8Data(
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

  ProbeSceneRowsV8Data copyWith({
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
  }) => ProbeSceneRowsV8Data(
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
  ProbeSceneRowsV8Data copyWithCompanion(ProbeSceneRowsV8Companion data) {
    return ProbeSceneRowsV8Data(
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
    return (StringBuffer('ProbeSceneRowsV8Data(')
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
      (other is ProbeSceneRowsV8Data &&
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

class ProbeSceneRowsV8Companion extends UpdateCompanion<ProbeSceneRowsV8Data> {
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
  const ProbeSceneRowsV8Companion({
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
  ProbeSceneRowsV8Companion.insert({
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
  static Insertable<ProbeSceneRowsV8Data> custom({
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

  ProbeSceneRowsV8Companion copyWith({
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
    return ProbeSceneRowsV8Companion(
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
    return (StringBuffer('ProbeSceneRowsV8Companion(')
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

abstract class _$ProbeDatabaseV8 extends GeneratedDatabase {
  _$ProbeDatabaseV8(QueryExecutor e) : super(e);
  $ProbeDatabaseV8Manager get managers => $ProbeDatabaseV8Manager(this);
  late final $ProbeSceneRowsV8Table probeSceneRowsV8 = $ProbeSceneRowsV8Table(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [probeSceneRowsV8];
}

typedef $$ProbeSceneRowsV8TableCreateCompanionBuilder =
    ProbeSceneRowsV8Companion Function({
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
typedef $$ProbeSceneRowsV8TableUpdateCompanionBuilder =
    ProbeSceneRowsV8Companion Function({
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

class $$ProbeSceneRowsV8TableFilterComposer
    extends Composer<_$ProbeDatabaseV8, $ProbeSceneRowsV8Table> {
  $$ProbeSceneRowsV8TableFilterComposer({
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

class $$ProbeSceneRowsV8TableOrderingComposer
    extends Composer<_$ProbeDatabaseV8, $ProbeSceneRowsV8Table> {
  $$ProbeSceneRowsV8TableOrderingComposer({
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

class $$ProbeSceneRowsV8TableAnnotationComposer
    extends Composer<_$ProbeDatabaseV8, $ProbeSceneRowsV8Table> {
  $$ProbeSceneRowsV8TableAnnotationComposer({
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

class $$ProbeSceneRowsV8TableTableManager
    extends
        RootTableManager<
          _$ProbeDatabaseV8,
          $ProbeSceneRowsV8Table,
          ProbeSceneRowsV8Data,
          $$ProbeSceneRowsV8TableFilterComposer,
          $$ProbeSceneRowsV8TableOrderingComposer,
          $$ProbeSceneRowsV8TableAnnotationComposer,
          $$ProbeSceneRowsV8TableCreateCompanionBuilder,
          $$ProbeSceneRowsV8TableUpdateCompanionBuilder,
          (
            ProbeSceneRowsV8Data,
            BaseReferences<
              _$ProbeDatabaseV8,
              $ProbeSceneRowsV8Table,
              ProbeSceneRowsV8Data
            >,
          ),
          ProbeSceneRowsV8Data,
          PrefetchHooks Function()
        > {
  $$ProbeSceneRowsV8TableTableManager(
    _$ProbeDatabaseV8 db,
    $ProbeSceneRowsV8Table table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProbeSceneRowsV8TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProbeSceneRowsV8TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProbeSceneRowsV8TableAnnotationComposer($db: db, $table: table),
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
              }) => ProbeSceneRowsV8Companion(
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
              }) => ProbeSceneRowsV8Companion.insert(
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
              .map(
                (e) => (
                  e.readTable<$ProbeSceneRowsV8Table, ProbeSceneRowsV8Data>(
                    table,
                  ),
                  BaseReferences<
                    _$ProbeDatabaseV8,
                    $ProbeSceneRowsV8Table,
                    ProbeSceneRowsV8Data
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProbeSceneRowsV8TableProcessedTableManager =
    ProcessedTableManager<
      _$ProbeDatabaseV8,
      $ProbeSceneRowsV8Table,
      ProbeSceneRowsV8Data,
      $$ProbeSceneRowsV8TableFilterComposer,
      $$ProbeSceneRowsV8TableOrderingComposer,
      $$ProbeSceneRowsV8TableAnnotationComposer,
      $$ProbeSceneRowsV8TableCreateCompanionBuilder,
      $$ProbeSceneRowsV8TableUpdateCompanionBuilder,
      (
        ProbeSceneRowsV8Data,
        BaseReferences<
          _$ProbeDatabaseV8,
          $ProbeSceneRowsV8Table,
          ProbeSceneRowsV8Data
        >,
      ),
      ProbeSceneRowsV8Data,
      PrefetchHooks Function()
    >;

class $ProbeDatabaseV8Manager {
  final _$ProbeDatabaseV8 _db;
  $ProbeDatabaseV8Manager(this._db);
  $$ProbeSceneRowsV8TableTableManager get probeSceneRowsV8 =>
      $$ProbeSceneRowsV8TableTableManager(_db, _db.probeSceneRowsV8);
}
