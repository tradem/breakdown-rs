// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'probe_schema_v2.dart';

// ignore_for_file: type=lint
class $ProbeRowsV2Table extends ProbeRowsV2
    with TableInfo<$ProbeRowsV2Table, ProbeRowsV2Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProbeRowsV2Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, archived];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'probe_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProbeRowsV2Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  ProbeRowsV2Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProbeRowsV2Data(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
    );
  }

  @override
  $ProbeRowsV2Table createAlias(String alias) {
    return $ProbeRowsV2Table(attachedDatabase, alias);
  }
}

class ProbeRowsV2Data extends DataClass implements Insertable<ProbeRowsV2Data> {
  final String id;
  final String name;
  final bool archived;
  const ProbeRowsV2Data({
    required this.id,
    required this.name,
    required this.archived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  ProbeRowsV2Companion toCompanion(bool nullToAbsent) {
    return ProbeRowsV2Companion(
      id: Value(id),
      name: Value(name),
      archived: Value(archived),
    );
  }

  factory ProbeRowsV2Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProbeRowsV2Data(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  ProbeRowsV2Data copyWith({String? id, String? name, bool? archived}) =>
      ProbeRowsV2Data(
        id: id ?? this.id,
        name: name ?? this.name,
        archived: archived ?? this.archived,
      );
  ProbeRowsV2Data copyWithCompanion(ProbeRowsV2Companion data) {
    return ProbeRowsV2Data(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProbeRowsV2Data(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProbeRowsV2Data &&
          other.id == this.id &&
          other.name == this.name &&
          other.archived == this.archived);
}

class ProbeRowsV2Companion extends UpdateCompanion<ProbeRowsV2Data> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> archived;
  final Value<int> rowid;
  const ProbeRowsV2Companion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.archived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProbeRowsV2Companion.insert({
    required String id,
    required String name,
    this.archived = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ProbeRowsV2Data> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? archived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (archived != null) 'archived': archived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProbeRowsV2Companion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? archived,
    Value<int>? rowid,
  }) {
    return ProbeRowsV2Companion(
      id: id ?? this.id,
      name: name ?? this.name,
      archived: archived ?? this.archived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProbeRowsV2Companion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('archived: $archived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProbeDatabaseV2 extends GeneratedDatabase {
  _$ProbeDatabaseV2(QueryExecutor e) : super(e);
  $ProbeDatabaseV2Manager get managers => $ProbeDatabaseV2Manager(this);
  late final $ProbeRowsV2Table probeRowsV2 = $ProbeRowsV2Table(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [probeRowsV2];
}

typedef $$ProbeRowsV2TableCreateCompanionBuilder =
    ProbeRowsV2Companion Function({
      required String id,
      required String name,
      Value<bool> archived,
      Value<int> rowid,
    });
typedef $$ProbeRowsV2TableUpdateCompanionBuilder =
    ProbeRowsV2Companion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> archived,
      Value<int> rowid,
    });

class $$ProbeRowsV2TableFilterComposer
    extends Composer<_$ProbeDatabaseV2, $ProbeRowsV2Table> {
  $$ProbeRowsV2TableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProbeRowsV2TableOrderingComposer
    extends Composer<_$ProbeDatabaseV2, $ProbeRowsV2Table> {
  $$ProbeRowsV2TableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProbeRowsV2TableAnnotationComposer
    extends Composer<_$ProbeDatabaseV2, $ProbeRowsV2Table> {
  $$ProbeRowsV2TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);
}

class $$ProbeRowsV2TableTableManager
    extends
        RootTableManager<
          _$ProbeDatabaseV2,
          $ProbeRowsV2Table,
          ProbeRowsV2Data,
          $$ProbeRowsV2TableFilterComposer,
          $$ProbeRowsV2TableOrderingComposer,
          $$ProbeRowsV2TableAnnotationComposer,
          $$ProbeRowsV2TableCreateCompanionBuilder,
          $$ProbeRowsV2TableUpdateCompanionBuilder,
          (
            ProbeRowsV2Data,
            BaseReferences<
              _$ProbeDatabaseV2,
              $ProbeRowsV2Table,
              ProbeRowsV2Data
            >,
          ),
          ProbeRowsV2Data,
          PrefetchHooks Function()
        > {
  $$ProbeRowsV2TableTableManager(_$ProbeDatabaseV2 db, $ProbeRowsV2Table table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProbeRowsV2TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProbeRowsV2TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProbeRowsV2TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProbeRowsV2Companion(
                id: id,
                name: name,
                archived: archived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> archived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProbeRowsV2Companion.insert(
                id: id,
                name: name,
                archived: archived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProbeRowsV2TableProcessedTableManager =
    ProcessedTableManager<
      _$ProbeDatabaseV2,
      $ProbeRowsV2Table,
      ProbeRowsV2Data,
      $$ProbeRowsV2TableFilterComposer,
      $$ProbeRowsV2TableOrderingComposer,
      $$ProbeRowsV2TableAnnotationComposer,
      $$ProbeRowsV2TableCreateCompanionBuilder,
      $$ProbeRowsV2TableUpdateCompanionBuilder,
      (
        ProbeRowsV2Data,
        BaseReferences<_$ProbeDatabaseV2, $ProbeRowsV2Table, ProbeRowsV2Data>,
      ),
      ProbeRowsV2Data,
      PrefetchHooks Function()
    >;

class $ProbeDatabaseV2Manager {
  final _$ProbeDatabaseV2 _db;
  $ProbeDatabaseV2Manager(this._db);
  $$ProbeRowsV2TableTableManager get probeRowsV2 =>
      $$ProbeRowsV2TableTableManager(_db, _db.probeRowsV2);
}
