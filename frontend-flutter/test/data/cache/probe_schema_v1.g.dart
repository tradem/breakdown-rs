// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'probe_schema_v1.dart';

// ignore_for_file: type=lint
class $ProbeRowsV1Table extends ProbeRowsV1
    with TableInfo<$ProbeRowsV1Table, ProbeRowsV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProbeRowsV1Table(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'probe_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProbeRowsV1Data> instance, {
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  ProbeRowsV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProbeRowsV1Data(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $ProbeRowsV1Table createAlias(String alias) {
    return $ProbeRowsV1Table(attachedDatabase, alias);
  }
}

class ProbeRowsV1Data extends DataClass implements Insertable<ProbeRowsV1Data> {
  final String id;
  final String name;
  const ProbeRowsV1Data({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  ProbeRowsV1Companion toCompanion(bool nullToAbsent) {
    return ProbeRowsV1Companion(id: Value(id), name: Value(name));
  }

  factory ProbeRowsV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProbeRowsV1Data(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  ProbeRowsV1Data copyWith({String? id, String? name}) =>
      ProbeRowsV1Data(id: id ?? this.id, name: name ?? this.name);
  ProbeRowsV1Data copyWithCompanion(ProbeRowsV1Companion data) {
    return ProbeRowsV1Data(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProbeRowsV1Data(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProbeRowsV1Data &&
          other.id == this.id &&
          other.name == this.name);
}

class ProbeRowsV1Companion extends UpdateCompanion<ProbeRowsV1Data> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const ProbeRowsV1Companion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProbeRowsV1Companion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ProbeRowsV1Data> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProbeRowsV1Companion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return ProbeRowsV1Companion(
      id: id ?? this.id,
      name: name ?? this.name,
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProbeRowsV1Companion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProbeDatabaseV1 extends GeneratedDatabase {
  _$ProbeDatabaseV1(QueryExecutor e) : super(e);
  $ProbeDatabaseV1Manager get managers => $ProbeDatabaseV1Manager(this);
  late final $ProbeRowsV1Table probeRowsV1 = $ProbeRowsV1Table(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [probeRowsV1];
}

typedef $$ProbeRowsV1TableCreateCompanionBuilder =
    ProbeRowsV1Companion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$ProbeRowsV1TableUpdateCompanionBuilder =
    ProbeRowsV1Companion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

class $$ProbeRowsV1TableFilterComposer
    extends Composer<_$ProbeDatabaseV1, $ProbeRowsV1Table> {
  $$ProbeRowsV1TableFilterComposer({
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
}

class $$ProbeRowsV1TableOrderingComposer
    extends Composer<_$ProbeDatabaseV1, $ProbeRowsV1Table> {
  $$ProbeRowsV1TableOrderingComposer({
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
}

class $$ProbeRowsV1TableAnnotationComposer
    extends Composer<_$ProbeDatabaseV1, $ProbeRowsV1Table> {
  $$ProbeRowsV1TableAnnotationComposer({
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
}

class $$ProbeRowsV1TableTableManager
    extends
        RootTableManager<
          _$ProbeDatabaseV1,
          $ProbeRowsV1Table,
          ProbeRowsV1Data,
          $$ProbeRowsV1TableFilterComposer,
          $$ProbeRowsV1TableOrderingComposer,
          $$ProbeRowsV1TableAnnotationComposer,
          $$ProbeRowsV1TableCreateCompanionBuilder,
          $$ProbeRowsV1TableUpdateCompanionBuilder,
          (
            ProbeRowsV1Data,
            BaseReferences<
              _$ProbeDatabaseV1,
              $ProbeRowsV1Table,
              ProbeRowsV1Data
            >,
          ),
          ProbeRowsV1Data,
          PrefetchHooks Function()
        > {
  $$ProbeRowsV1TableTableManager(_$ProbeDatabaseV1 db, $ProbeRowsV1Table table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProbeRowsV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProbeRowsV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProbeRowsV1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => ProbeRowsV1Companion(id: id, name: name, rowid: rowid),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<int> rowid = const Value.absent(),
          }) => ProbeRowsV1Companion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProbeRowsV1TableProcessedTableManager =
    ProcessedTableManager<
      _$ProbeDatabaseV1,
      $ProbeRowsV1Table,
      ProbeRowsV1Data,
      $$ProbeRowsV1TableFilterComposer,
      $$ProbeRowsV1TableOrderingComposer,
      $$ProbeRowsV1TableAnnotationComposer,
      $$ProbeRowsV1TableCreateCompanionBuilder,
      $$ProbeRowsV1TableUpdateCompanionBuilder,
      (
        ProbeRowsV1Data,
        BaseReferences<_$ProbeDatabaseV1, $ProbeRowsV1Table, ProbeRowsV1Data>,
      ),
      ProbeRowsV1Data,
      PrefetchHooks Function()
    >;

class $ProbeDatabaseV1Manager {
  final _$ProbeDatabaseV1 _db;
  $ProbeDatabaseV1Manager(this._db);
  $$ProbeRowsV1TableTableManager get probeRowsV1 =>
      $$ProbeRowsV1TableTableManager(_db, _db.probeRowsV1);
}
