// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $GraphNodesTable extends GraphNodes
    with TableInfo<$GraphNodesTable, GraphNodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GraphNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conceptMeta = const VerificationMeta(
    'concept',
  );
  @override
  late final GeneratedColumn<String> concept = GeneratedColumn<String>(
    'concept',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrereqMeta = const VerificationMeta(
    'isPrereq',
  );
  @override
  late final GeneratedColumn<bool> isPrereq = GeneratedColumn<bool>(
    'is_prereq',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_prereq" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceArticlesJsonMeta =
      const VerificationMeta('sourceArticlesJson');
  @override
  late final GeneratedColumn<String> sourceArticlesJson =
      GeneratedColumn<String>(
        'source_articles_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _summaryMetaMeta = const VerificationMeta(
    'summaryMeta',
  );
  @override
  late final GeneratedColumn<String> summaryMeta = GeneratedColumn<String>(
    'summary_meta',
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    concept,
    state,
    isPrereq,
    sourceArticlesJson,
    summaryMeta,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphNodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('concept')) {
      context.handle(
        _conceptMeta,
        concept.isAcceptableOrUnknown(data['concept']!, _conceptMeta),
      );
    } else if (isInserting) {
      context.missing(_conceptMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('is_prereq')) {
      context.handle(
        _isPrereqMeta,
        isPrereq.isAcceptableOrUnknown(data['is_prereq']!, _isPrereqMeta),
      );
    }
    if (data.containsKey('source_articles_json')) {
      context.handle(
        _sourceArticlesJsonMeta,
        sourceArticlesJson.isAcceptableOrUnknown(
          data['source_articles_json']!,
          _sourceArticlesJsonMeta,
        ),
      );
    }
    if (data.containsKey('summary_meta')) {
      context.handle(
        _summaryMetaMeta,
        summaryMeta.isAcceptableOrUnknown(
          data['summary_meta']!,
          _summaryMetaMeta,
        ),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GraphNodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphNodeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      concept: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concept'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      isPrereq: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_prereq'],
      )!,
      sourceArticlesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_articles_json'],
      )!,
      summaryMeta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_meta'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $GraphNodesTable createAlias(String alias) {
    return $GraphNodesTable(attachedDatabase, alias);
  }
}

class GraphNodeRow extends DataClass implements Insertable<GraphNodeRow> {
  final String id;
  final String concept;

  /// understood / not_understood / unknown. 미지의 값도 그대로 보존한다.
  final String state;
  final bool isPrereq;

  /// 출처 기사 제목 목록을 JSON 배열 문자열로 보관.
  final String sourceArticlesJson;

  /// 개인화 요약이 흡수된 자리(명세 §4.4).
  final String? summaryMeta;
  final DateTime updatedAt;
  const GraphNodeRow({
    required this.id,
    required this.concept,
    required this.state,
    required this.isPrereq,
    required this.sourceArticlesJson,
    this.summaryMeta,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['concept'] = Variable<String>(concept);
    map['state'] = Variable<String>(state);
    map['is_prereq'] = Variable<bool>(isPrereq);
    map['source_articles_json'] = Variable<String>(sourceArticlesJson);
    if (!nullToAbsent || summaryMeta != null) {
      map['summary_meta'] = Variable<String>(summaryMeta);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  GraphNodesCompanion toCompanion(bool nullToAbsent) {
    return GraphNodesCompanion(
      id: Value(id),
      concept: Value(concept),
      state: Value(state),
      isPrereq: Value(isPrereq),
      sourceArticlesJson: Value(sourceArticlesJson),
      summaryMeta: summaryMeta == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryMeta),
      updatedAt: Value(updatedAt),
    );
  }

  factory GraphNodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphNodeRow(
      id: serializer.fromJson<String>(json['id']),
      concept: serializer.fromJson<String>(json['concept']),
      state: serializer.fromJson<String>(json['state']),
      isPrereq: serializer.fromJson<bool>(json['isPrereq']),
      sourceArticlesJson: serializer.fromJson<String>(
        json['sourceArticlesJson'],
      ),
      summaryMeta: serializer.fromJson<String?>(json['summaryMeta']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'concept': serializer.toJson<String>(concept),
      'state': serializer.toJson<String>(state),
      'isPrereq': serializer.toJson<bool>(isPrereq),
      'sourceArticlesJson': serializer.toJson<String>(sourceArticlesJson),
      'summaryMeta': serializer.toJson<String?>(summaryMeta),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  GraphNodeRow copyWith({
    String? id,
    String? concept,
    String? state,
    bool? isPrereq,
    String? sourceArticlesJson,
    Value<String?> summaryMeta = const Value.absent(),
    DateTime? updatedAt,
  }) => GraphNodeRow(
    id: id ?? this.id,
    concept: concept ?? this.concept,
    state: state ?? this.state,
    isPrereq: isPrereq ?? this.isPrereq,
    sourceArticlesJson: sourceArticlesJson ?? this.sourceArticlesJson,
    summaryMeta: summaryMeta.present ? summaryMeta.value : this.summaryMeta,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  GraphNodeRow copyWithCompanion(GraphNodesCompanion data) {
    return GraphNodeRow(
      id: data.id.present ? data.id.value : this.id,
      concept: data.concept.present ? data.concept.value : this.concept,
      state: data.state.present ? data.state.value : this.state,
      isPrereq: data.isPrereq.present ? data.isPrereq.value : this.isPrereq,
      sourceArticlesJson: data.sourceArticlesJson.present
          ? data.sourceArticlesJson.value
          : this.sourceArticlesJson,
      summaryMeta: data.summaryMeta.present
          ? data.summaryMeta.value
          : this.summaryMeta,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphNodeRow(')
          ..write('id: $id, ')
          ..write('concept: $concept, ')
          ..write('state: $state, ')
          ..write('isPrereq: $isPrereq, ')
          ..write('sourceArticlesJson: $sourceArticlesJson, ')
          ..write('summaryMeta: $summaryMeta, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    concept,
    state,
    isPrereq,
    sourceArticlesJson,
    summaryMeta,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphNodeRow &&
          other.id == this.id &&
          other.concept == this.concept &&
          other.state == this.state &&
          other.isPrereq == this.isPrereq &&
          other.sourceArticlesJson == this.sourceArticlesJson &&
          other.summaryMeta == this.summaryMeta &&
          other.updatedAt == this.updatedAt);
}

class GraphNodesCompanion extends UpdateCompanion<GraphNodeRow> {
  final Value<String> id;
  final Value<String> concept;
  final Value<String> state;
  final Value<bool> isPrereq;
  final Value<String> sourceArticlesJson;
  final Value<String?> summaryMeta;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const GraphNodesCompanion({
    this.id = const Value.absent(),
    this.concept = const Value.absent(),
    this.state = const Value.absent(),
    this.isPrereq = const Value.absent(),
    this.sourceArticlesJson = const Value.absent(),
    this.summaryMeta = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphNodesCompanion.insert({
    required String id,
    required String concept,
    required String state,
    this.isPrereq = const Value.absent(),
    this.sourceArticlesJson = const Value.absent(),
    this.summaryMeta = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       concept = Value(concept),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<GraphNodeRow> custom({
    Expression<String>? id,
    Expression<String>? concept,
    Expression<String>? state,
    Expression<bool>? isPrereq,
    Expression<String>? sourceArticlesJson,
    Expression<String>? summaryMeta,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (concept != null) 'concept': concept,
      if (state != null) 'state': state,
      if (isPrereq != null) 'is_prereq': isPrereq,
      if (sourceArticlesJson != null)
        'source_articles_json': sourceArticlesJson,
      if (summaryMeta != null) 'summary_meta': summaryMeta,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphNodesCompanion copyWith({
    Value<String>? id,
    Value<String>? concept,
    Value<String>? state,
    Value<bool>? isPrereq,
    Value<String>? sourceArticlesJson,
    Value<String?>? summaryMeta,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return GraphNodesCompanion(
      id: id ?? this.id,
      concept: concept ?? this.concept,
      state: state ?? this.state,
      isPrereq: isPrereq ?? this.isPrereq,
      sourceArticlesJson: sourceArticlesJson ?? this.sourceArticlesJson,
      summaryMeta: summaryMeta ?? this.summaryMeta,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (concept.present) {
      map['concept'] = Variable<String>(concept.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (isPrereq.present) {
      map['is_prereq'] = Variable<bool>(isPrereq.value);
    }
    if (sourceArticlesJson.present) {
      map['source_articles_json'] = Variable<String>(sourceArticlesJson.value);
    }
    if (summaryMeta.present) {
      map['summary_meta'] = Variable<String>(summaryMeta.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphNodesCompanion(')
          ..write('id: $id, ')
          ..write('concept: $concept, ')
          ..write('state: $state, ')
          ..write('isPrereq: $isPrereq, ')
          ..write('sourceArticlesJson: $sourceArticlesJson, ')
          ..write('summaryMeta: $summaryMeta, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GraphEdgesTable extends GraphEdges
    with TableInfo<$GraphEdgesTable, GraphEdgeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GraphEdgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fromIdMeta = const VerificationMeta('fromId');
  @override
  late final GeneratedColumn<String> fromId = GeneratedColumn<String>(
    'from_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toIdMeta = const VerificationMeta('toId');
  @override
  late final GeneratedColumn<String> toId = GeneratedColumn<String>(
    'to_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [fromId, toId, type];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graph_edges';
  @override
  VerificationContext validateIntegrity(
    Insertable<GraphEdgeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('from_id')) {
      context.handle(
        _fromIdMeta,
        fromId.isAcceptableOrUnknown(data['from_id']!, _fromIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fromIdMeta);
    }
    if (data.containsKey('to_id')) {
      context.handle(
        _toIdMeta,
        toId.isAcceptableOrUnknown(data['to_id']!, _toIdMeta),
      );
    } else if (isInserting) {
      context.missing(_toIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fromId, toId, type};
  @override
  GraphEdgeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GraphEdgeRow(
      fromId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_id'],
      )!,
      toId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
    );
  }

  @override
  $GraphEdgesTable createAlias(String alias) {
    return $GraphEdgesTable(attachedDatabase, alias);
  }
}

class GraphEdgeRow extends DataClass implements Insertable<GraphEdgeRow> {
  final String fromId;
  final String toId;
  final String type;
  const GraphEdgeRow({
    required this.fromId,
    required this.toId,
    required this.type,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['from_id'] = Variable<String>(fromId);
    map['to_id'] = Variable<String>(toId);
    map['type'] = Variable<String>(type);
    return map;
  }

  GraphEdgesCompanion toCompanion(bool nullToAbsent) {
    return GraphEdgesCompanion(
      fromId: Value(fromId),
      toId: Value(toId),
      type: Value(type),
    );
  }

  factory GraphEdgeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GraphEdgeRow(
      fromId: serializer.fromJson<String>(json['fromId']),
      toId: serializer.fromJson<String>(json['toId']),
      type: serializer.fromJson<String>(json['type']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fromId': serializer.toJson<String>(fromId),
      'toId': serializer.toJson<String>(toId),
      'type': serializer.toJson<String>(type),
    };
  }

  GraphEdgeRow copyWith({String? fromId, String? toId, String? type}) =>
      GraphEdgeRow(
        fromId: fromId ?? this.fromId,
        toId: toId ?? this.toId,
        type: type ?? this.type,
      );
  GraphEdgeRow copyWithCompanion(GraphEdgesCompanion data) {
    return GraphEdgeRow(
      fromId: data.fromId.present ? data.fromId.value : this.fromId,
      toId: data.toId.present ? data.toId.value : this.toId,
      type: data.type.present ? data.type.value : this.type,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GraphEdgeRow(')
          ..write('fromId: $fromId, ')
          ..write('toId: $toId, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fromId, toId, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphEdgeRow &&
          other.fromId == this.fromId &&
          other.toId == this.toId &&
          other.type == this.type);
}

class GraphEdgesCompanion extends UpdateCompanion<GraphEdgeRow> {
  final Value<String> fromId;
  final Value<String> toId;
  final Value<String> type;
  final Value<int> rowid;
  const GraphEdgesCompanion({
    this.fromId = const Value.absent(),
    this.toId = const Value.absent(),
    this.type = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GraphEdgesCompanion.insert({
    required String fromId,
    required String toId,
    required String type,
    this.rowid = const Value.absent(),
  }) : fromId = Value(fromId),
       toId = Value(toId),
       type = Value(type);
  static Insertable<GraphEdgeRow> custom({
    Expression<String>? fromId,
    Expression<String>? toId,
    Expression<String>? type,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fromId != null) 'from_id': fromId,
      if (toId != null) 'to_id': toId,
      if (type != null) 'type': type,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GraphEdgesCompanion copyWith({
    Value<String>? fromId,
    Value<String>? toId,
    Value<String>? type,
    Value<int>? rowid,
  }) {
    return GraphEdgesCompanion(
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      type: type ?? this.type,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fromId.present) {
      map['from_id'] = Variable<String>(fromId.value);
    }
    if (toId.present) {
      map['to_id'] = Variable<String>(toId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GraphEdgesCompanion(')
          ..write('fromId: $fromId, ')
          ..write('toId: $toId, ')
          ..write('type: $type, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningHistoriesTable extends LearningHistories
    with TableInfo<$LearningHistoriesTable, LearningHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conceptTagMeta = const VerificationMeta(
    'conceptTag',
  );
  @override
  late final GeneratedColumn<String> conceptTag = GeneratedColumn<String>(
    'concept_tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentConceptMeta = const VerificationMeta(
    'parentConcept',
  );
  @override
  late final GeneratedColumn<String> parentConcept = GeneratedColumn<String>(
    'parent_concept',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _correctMeta = const VerificationMeta(
    'correct',
  );
  @override
  late final GeneratedColumn<bool> correct = GeneratedColumn<bool>(
    'correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _articleTitleMeta = const VerificationMeta(
    'articleTitle',
  );
  @override
  late final GeneratedColumn<String> articleTitle = GeneratedColumn<String>(
    'article_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conceptTag,
    parentConcept,
    level,
    correct,
    articleTitle,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('concept_tag')) {
      context.handle(
        _conceptTagMeta,
        conceptTag.isAcceptableOrUnknown(data['concept_tag']!, _conceptTagMeta),
      );
    } else if (isInserting) {
      context.missing(_conceptTagMeta);
    }
    if (data.containsKey('parent_concept')) {
      context.handle(
        _parentConceptMeta,
        parentConcept.isAcceptableOrUnknown(
          data['parent_concept']!,
          _parentConceptMeta,
        ),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('correct')) {
      context.handle(
        _correctMeta,
        correct.isAcceptableOrUnknown(data['correct']!, _correctMeta),
      );
    } else if (isInserting) {
      context.missing(_correctMeta);
    }
    if (data.containsKey('article_title')) {
      context.handle(
        _articleTitleMeta,
        articleTitle.isAcceptableOrUnknown(
          data['article_title']!,
          _articleTitleMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conceptTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concept_tag'],
      )!,
      parentConcept: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_concept'],
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      correct: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correct'],
      )!,
      articleTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}article_title'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $LearningHistoriesTable createAlias(String alias) {
    return $LearningHistoriesTable(attachedDatabase, alias);
  }
}

class LearningHistoryRow extends DataClass
    implements Insertable<LearningHistoryRow> {
  final int id;
  final String conceptTag;

  /// null이면 main 문항(구현계획① §3.5).
  final String? parentConcept;
  final int level;
  final bool correct;
  final String? articleTitle;
  final DateTime occurredAt;
  const LearningHistoryRow({
    required this.id,
    required this.conceptTag,
    this.parentConcept,
    required this.level,
    required this.correct,
    this.articleTitle,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['concept_tag'] = Variable<String>(conceptTag);
    if (!nullToAbsent || parentConcept != null) {
      map['parent_concept'] = Variable<String>(parentConcept);
    }
    map['level'] = Variable<int>(level);
    map['correct'] = Variable<bool>(correct);
    if (!nullToAbsent || articleTitle != null) {
      map['article_title'] = Variable<String>(articleTitle);
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  LearningHistoriesCompanion toCompanion(bool nullToAbsent) {
    return LearningHistoriesCompanion(
      id: Value(id),
      conceptTag: Value(conceptTag),
      parentConcept: parentConcept == null && nullToAbsent
          ? const Value.absent()
          : Value(parentConcept),
      level: Value(level),
      correct: Value(correct),
      articleTitle: articleTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(articleTitle),
      occurredAt: Value(occurredAt),
    );
  }

  factory LearningHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      conceptTag: serializer.fromJson<String>(json['conceptTag']),
      parentConcept: serializer.fromJson<String?>(json['parentConcept']),
      level: serializer.fromJson<int>(json['level']),
      correct: serializer.fromJson<bool>(json['correct']),
      articleTitle: serializer.fromJson<String?>(json['articleTitle']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conceptTag': serializer.toJson<String>(conceptTag),
      'parentConcept': serializer.toJson<String?>(parentConcept),
      'level': serializer.toJson<int>(level),
      'correct': serializer.toJson<bool>(correct),
      'articleTitle': serializer.toJson<String?>(articleTitle),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  LearningHistoryRow copyWith({
    int? id,
    String? conceptTag,
    Value<String?> parentConcept = const Value.absent(),
    int? level,
    bool? correct,
    Value<String?> articleTitle = const Value.absent(),
    DateTime? occurredAt,
  }) => LearningHistoryRow(
    id: id ?? this.id,
    conceptTag: conceptTag ?? this.conceptTag,
    parentConcept: parentConcept.present
        ? parentConcept.value
        : this.parentConcept,
    level: level ?? this.level,
    correct: correct ?? this.correct,
    articleTitle: articleTitle.present ? articleTitle.value : this.articleTitle,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  LearningHistoryRow copyWithCompanion(LearningHistoriesCompanion data) {
    return LearningHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      conceptTag: data.conceptTag.present
          ? data.conceptTag.value
          : this.conceptTag,
      parentConcept: data.parentConcept.present
          ? data.parentConcept.value
          : this.parentConcept,
      level: data.level.present ? data.level.value : this.level,
      correct: data.correct.present ? data.correct.value : this.correct,
      articleTitle: data.articleTitle.present
          ? data.articleTitle.value
          : this.articleTitle,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningHistoryRow(')
          ..write('id: $id, ')
          ..write('conceptTag: $conceptTag, ')
          ..write('parentConcept: $parentConcept, ')
          ..write('level: $level, ')
          ..write('correct: $correct, ')
          ..write('articleTitle: $articleTitle, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conceptTag,
    parentConcept,
    level,
    correct,
    articleTitle,
    occurredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningHistoryRow &&
          other.id == this.id &&
          other.conceptTag == this.conceptTag &&
          other.parentConcept == this.parentConcept &&
          other.level == this.level &&
          other.correct == this.correct &&
          other.articleTitle == this.articleTitle &&
          other.occurredAt == this.occurredAt);
}

class LearningHistoriesCompanion extends UpdateCompanion<LearningHistoryRow> {
  final Value<int> id;
  final Value<String> conceptTag;
  final Value<String?> parentConcept;
  final Value<int> level;
  final Value<bool> correct;
  final Value<String?> articleTitle;
  final Value<DateTime> occurredAt;
  const LearningHistoriesCompanion({
    this.id = const Value.absent(),
    this.conceptTag = const Value.absent(),
    this.parentConcept = const Value.absent(),
    this.level = const Value.absent(),
    this.correct = const Value.absent(),
    this.articleTitle = const Value.absent(),
    this.occurredAt = const Value.absent(),
  });
  LearningHistoriesCompanion.insert({
    this.id = const Value.absent(),
    required String conceptTag,
    this.parentConcept = const Value.absent(),
    this.level = const Value.absent(),
    required bool correct,
    this.articleTitle = const Value.absent(),
    required DateTime occurredAt,
  }) : conceptTag = Value(conceptTag),
       correct = Value(correct),
       occurredAt = Value(occurredAt);
  static Insertable<LearningHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? conceptTag,
    Expression<String>? parentConcept,
    Expression<int>? level,
    Expression<bool>? correct,
    Expression<String>? articleTitle,
    Expression<DateTime>? occurredAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conceptTag != null) 'concept_tag': conceptTag,
      if (parentConcept != null) 'parent_concept': parentConcept,
      if (level != null) 'level': level,
      if (correct != null) 'correct': correct,
      if (articleTitle != null) 'article_title': articleTitle,
      if (occurredAt != null) 'occurred_at': occurredAt,
    });
  }

  LearningHistoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? conceptTag,
    Value<String?>? parentConcept,
    Value<int>? level,
    Value<bool>? correct,
    Value<String?>? articleTitle,
    Value<DateTime>? occurredAt,
  }) {
    return LearningHistoriesCompanion(
      id: id ?? this.id,
      conceptTag: conceptTag ?? this.conceptTag,
      parentConcept: parentConcept ?? this.parentConcept,
      level: level ?? this.level,
      correct: correct ?? this.correct,
      articleTitle: articleTitle ?? this.articleTitle,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conceptTag.present) {
      map['concept_tag'] = Variable<String>(conceptTag.value);
    }
    if (parentConcept.present) {
      map['parent_concept'] = Variable<String>(parentConcept.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (correct.present) {
      map['correct'] = Variable<bool>(correct.value);
    }
    if (articleTitle.present) {
      map['article_title'] = Variable<String>(articleTitle.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningHistoriesCompanion(')
          ..write('id: $id, ')
          ..write('conceptTag: $conceptTag, ')
          ..write('parentConcept: $parentConcept, ')
          ..write('level: $level, ')
          ..write('correct: $correct, ')
          ..write('articleTitle: $articleTitle, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }
}

class $ArticlePreferencesTable extends ArticlePreferences
    with TableInfo<$ArticlePreferencesTable, ArticlePreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticlePreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keywordMeta = const VerificationMeta(
    'keyword',
  );
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
    'keyword',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [keyword, category, weight, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArticlePreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('keyword')) {
      context.handle(
        _keywordMeta,
        keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyword};
  @override
  ArticlePreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticlePreferenceRow(
      keyword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keyword'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ArticlePreferencesTable createAlias(String alias) {
    return $ArticlePreferencesTable(attachedDatabase, alias);
  }
}

class ArticlePreferenceRow extends DataClass
    implements Insertable<ArticlePreferenceRow> {
  final String keyword;
  final String? category;
  final double weight;
  final DateTime updatedAt;
  const ArticlePreferenceRow({
    required this.keyword,
    this.category,
    required this.weight,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['keyword'] = Variable<String>(keyword);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['weight'] = Variable<double>(weight);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ArticlePreferencesCompanion toCompanion(bool nullToAbsent) {
    return ArticlePreferencesCompanion(
      keyword: Value(keyword),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      weight: Value(weight),
      updatedAt: Value(updatedAt),
    );
  }

  factory ArticlePreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticlePreferenceRow(
      keyword: serializer.fromJson<String>(json['keyword']),
      category: serializer.fromJson<String?>(json['category']),
      weight: serializer.fromJson<double>(json['weight']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyword': serializer.toJson<String>(keyword),
      'category': serializer.toJson<String?>(category),
      'weight': serializer.toJson<double>(weight),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ArticlePreferenceRow copyWith({
    String? keyword,
    Value<String?> category = const Value.absent(),
    double? weight,
    DateTime? updatedAt,
  }) => ArticlePreferenceRow(
    keyword: keyword ?? this.keyword,
    category: category.present ? category.value : this.category,
    weight: weight ?? this.weight,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ArticlePreferenceRow copyWithCompanion(ArticlePreferencesCompanion data) {
    return ArticlePreferenceRow(
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      category: data.category.present ? data.category.value : this.category,
      weight: data.weight.present ? data.weight.value : this.weight,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticlePreferenceRow(')
          ..write('keyword: $keyword, ')
          ..write('category: $category, ')
          ..write('weight: $weight, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyword, category, weight, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticlePreferenceRow &&
          other.keyword == this.keyword &&
          other.category == this.category &&
          other.weight == this.weight &&
          other.updatedAt == this.updatedAt);
}

class ArticlePreferencesCompanion
    extends UpdateCompanion<ArticlePreferenceRow> {
  final Value<String> keyword;
  final Value<String?> category;
  final Value<double> weight;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ArticlePreferencesCompanion({
    this.keyword = const Value.absent(),
    this.category = const Value.absent(),
    this.weight = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArticlePreferencesCompanion.insert({
    required String keyword,
    this.category = const Value.absent(),
    this.weight = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : keyword = Value(keyword),
       updatedAt = Value(updatedAt);
  static Insertable<ArticlePreferenceRow> custom({
    Expression<String>? keyword,
    Expression<String>? category,
    Expression<double>? weight,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyword != null) 'keyword': keyword,
      if (category != null) 'category': category,
      if (weight != null) 'weight': weight,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArticlePreferencesCompanion copyWith({
    Value<String>? keyword,
    Value<String?>? category,
    Value<double>? weight,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ArticlePreferencesCompanion(
      keyword: keyword ?? this.keyword,
      category: category ?? this.category,
      weight: weight ?? this.weight,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticlePreferencesCompanion(')
          ..write('keyword: $keyword, ')
          ..write('category: $category, ')
          ..write('weight: $weight, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppliedScrapsTable extends AppliedScraps
    with TableInfo<$AppliedScrapsTable, AppliedScrapRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppliedScrapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _articleTitleMeta = const VerificationMeta(
    'articleTitle',
  );
  @override
  late final GeneratedColumn<String> articleTitle = GeneratedColumn<String>(
    'article_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeCountMeta = const VerificationMeta(
    'nodeCount',
  );
  @override
  late final GeneratedColumn<int> nodeCount = GeneratedColumn<int>(
    'node_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _appliedAtMeta = const VerificationMeta(
    'appliedAt',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAt = GeneratedColumn<DateTime>(
    'applied_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    articleTitle,
    nodeCount,
    appliedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'applied_scraps';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppliedScrapRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('article_title')) {
      context.handle(
        _articleTitleMeta,
        articleTitle.isAcceptableOrUnknown(
          data['article_title']!,
          _articleTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_articleTitleMeta);
    }
    if (data.containsKey('node_count')) {
      context.handle(
        _nodeCountMeta,
        nodeCount.isAcceptableOrUnknown(data['node_count']!, _nodeCountMeta),
      );
    }
    if (data.containsKey('applied_at')) {
      context.handle(
        _appliedAtMeta,
        appliedAt.isAcceptableOrUnknown(data['applied_at']!, _appliedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_appliedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppliedScrapRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppliedScrapRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      articleTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}article_title'],
      )!,
      nodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}node_count'],
      )!,
      appliedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}applied_at'],
      )!,
    );
  }

  @override
  $AppliedScrapsTable createAlias(String alias) {
    return $AppliedScrapsTable(attachedDatabase, alias);
  }
}

class AppliedScrapRow extends DataClass implements Insertable<AppliedScrapRow> {
  final int id;
  final String articleTitle;
  final int nodeCount;
  final DateTime appliedAt;
  const AppliedScrapRow({
    required this.id,
    required this.articleTitle,
    required this.nodeCount,
    required this.appliedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['article_title'] = Variable<String>(articleTitle);
    map['node_count'] = Variable<int>(nodeCount);
    map['applied_at'] = Variable<DateTime>(appliedAt);
    return map;
  }

  AppliedScrapsCompanion toCompanion(bool nullToAbsent) {
    return AppliedScrapsCompanion(
      id: Value(id),
      articleTitle: Value(articleTitle),
      nodeCount: Value(nodeCount),
      appliedAt: Value(appliedAt),
    );
  }

  factory AppliedScrapRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppliedScrapRow(
      id: serializer.fromJson<int>(json['id']),
      articleTitle: serializer.fromJson<String>(json['articleTitle']),
      nodeCount: serializer.fromJson<int>(json['nodeCount']),
      appliedAt: serializer.fromJson<DateTime>(json['appliedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'articleTitle': serializer.toJson<String>(articleTitle),
      'nodeCount': serializer.toJson<int>(nodeCount),
      'appliedAt': serializer.toJson<DateTime>(appliedAt),
    };
  }

  AppliedScrapRow copyWith({
    int? id,
    String? articleTitle,
    int? nodeCount,
    DateTime? appliedAt,
  }) => AppliedScrapRow(
    id: id ?? this.id,
    articleTitle: articleTitle ?? this.articleTitle,
    nodeCount: nodeCount ?? this.nodeCount,
    appliedAt: appliedAt ?? this.appliedAt,
  );
  AppliedScrapRow copyWithCompanion(AppliedScrapsCompanion data) {
    return AppliedScrapRow(
      id: data.id.present ? data.id.value : this.id,
      articleTitle: data.articleTitle.present
          ? data.articleTitle.value
          : this.articleTitle,
      nodeCount: data.nodeCount.present ? data.nodeCount.value : this.nodeCount,
      appliedAt: data.appliedAt.present ? data.appliedAt.value : this.appliedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppliedScrapRow(')
          ..write('id: $id, ')
          ..write('articleTitle: $articleTitle, ')
          ..write('nodeCount: $nodeCount, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, articleTitle, nodeCount, appliedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppliedScrapRow &&
          other.id == this.id &&
          other.articleTitle == this.articleTitle &&
          other.nodeCount == this.nodeCount &&
          other.appliedAt == this.appliedAt);
}

class AppliedScrapsCompanion extends UpdateCompanion<AppliedScrapRow> {
  final Value<int> id;
  final Value<String> articleTitle;
  final Value<int> nodeCount;
  final Value<DateTime> appliedAt;
  const AppliedScrapsCompanion({
    this.id = const Value.absent(),
    this.articleTitle = const Value.absent(),
    this.nodeCount = const Value.absent(),
    this.appliedAt = const Value.absent(),
  });
  AppliedScrapsCompanion.insert({
    this.id = const Value.absent(),
    required String articleTitle,
    this.nodeCount = const Value.absent(),
    required DateTime appliedAt,
  }) : articleTitle = Value(articleTitle),
       appliedAt = Value(appliedAt);
  static Insertable<AppliedScrapRow> custom({
    Expression<int>? id,
    Expression<String>? articleTitle,
    Expression<int>? nodeCount,
    Expression<DateTime>? appliedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (articleTitle != null) 'article_title': articleTitle,
      if (nodeCount != null) 'node_count': nodeCount,
      if (appliedAt != null) 'applied_at': appliedAt,
    });
  }

  AppliedScrapsCompanion copyWith({
    Value<int>? id,
    Value<String>? articleTitle,
    Value<int>? nodeCount,
    Value<DateTime>? appliedAt,
  }) {
    return AppliedScrapsCompanion(
      id: id ?? this.id,
      articleTitle: articleTitle ?? this.articleTitle,
      nodeCount: nodeCount ?? this.nodeCount,
      appliedAt: appliedAt ?? this.appliedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (articleTitle.present) {
      map['article_title'] = Variable<String>(articleTitle.value);
    }
    if (nodeCount.present) {
      map['node_count'] = Variable<int>(nodeCount.value);
    }
    if (appliedAt.present) {
      map['applied_at'] = Variable<DateTime>(appliedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppliedScrapsCompanion(')
          ..write('id: $id, ')
          ..write('articleTitle: $articleTitle, ')
          ..write('nodeCount: $nodeCount, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GraphNodesTable graphNodes = $GraphNodesTable(this);
  late final $GraphEdgesTable graphEdges = $GraphEdgesTable(this);
  late final $LearningHistoriesTable learningHistories =
      $LearningHistoriesTable(this);
  late final $ArticlePreferencesTable articlePreferences =
      $ArticlePreferencesTable(this);
  late final $AppliedScrapsTable appliedScraps = $AppliedScrapsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    graphNodes,
    graphEdges,
    learningHistories,
    articlePreferences,
    appliedScraps,
  ];
}

typedef $$GraphNodesTableCreateCompanionBuilder =
    GraphNodesCompanion Function({
      required String id,
      required String concept,
      required String state,
      Value<bool> isPrereq,
      Value<String> sourceArticlesJson,
      Value<String?> summaryMeta,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$GraphNodesTableUpdateCompanionBuilder =
    GraphNodesCompanion Function({
      Value<String> id,
      Value<String> concept,
      Value<String> state,
      Value<bool> isPrereq,
      Value<String> sourceArticlesJson,
      Value<String?> summaryMeta,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$GraphNodesTableFilterComposer
    extends Composer<_$AppDatabase, $GraphNodesTable> {
  $$GraphNodesTableFilterComposer({
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

  ColumnFilters<String> get concept => $composableBuilder(
    column: $table.concept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrereq => $composableBuilder(
    column: $table.isPrereq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceArticlesJson => $composableBuilder(
    column: $table.sourceArticlesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryMeta => $composableBuilder(
    column: $table.summaryMeta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GraphNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $GraphNodesTable> {
  $$GraphNodesTableOrderingComposer({
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

  ColumnOrderings<String> get concept => $composableBuilder(
    column: $table.concept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrereq => $composableBuilder(
    column: $table.isPrereq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceArticlesJson => $composableBuilder(
    column: $table.sourceArticlesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryMeta => $composableBuilder(
    column: $table.summaryMeta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GraphNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GraphNodesTable> {
  $$GraphNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get concept =>
      $composableBuilder(column: $table.concept, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<bool> get isPrereq =>
      $composableBuilder(column: $table.isPrereq, builder: (column) => column);

  GeneratedColumn<String> get sourceArticlesJson => $composableBuilder(
    column: $table.sourceArticlesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryMeta => $composableBuilder(
    column: $table.summaryMeta,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$GraphNodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GraphNodesTable,
          GraphNodeRow,
          $$GraphNodesTableFilterComposer,
          $$GraphNodesTableOrderingComposer,
          $$GraphNodesTableAnnotationComposer,
          $$GraphNodesTableCreateCompanionBuilder,
          $$GraphNodesTableUpdateCompanionBuilder,
          (
            GraphNodeRow,
            BaseReferences<_$AppDatabase, $GraphNodesTable, GraphNodeRow>,
          ),
          GraphNodeRow,
          PrefetchHooks Function()
        > {
  $$GraphNodesTableTableManager(_$AppDatabase db, $GraphNodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GraphNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GraphNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GraphNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> concept = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<bool> isPrereq = const Value.absent(),
                Value<String> sourceArticlesJson = const Value.absent(),
                Value<String?> summaryMeta = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphNodesCompanion(
                id: id,
                concept: concept,
                state: state,
                isPrereq: isPrereq,
                sourceArticlesJson: sourceArticlesJson,
                summaryMeta: summaryMeta,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String concept,
                required String state,
                Value<bool> isPrereq = const Value.absent(),
                Value<String> sourceArticlesJson = const Value.absent(),
                Value<String?> summaryMeta = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => GraphNodesCompanion.insert(
                id: id,
                concept: concept,
                state: state,
                isPrereq: isPrereq,
                sourceArticlesJson: sourceArticlesJson,
                summaryMeta: summaryMeta,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GraphNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GraphNodesTable,
      GraphNodeRow,
      $$GraphNodesTableFilterComposer,
      $$GraphNodesTableOrderingComposer,
      $$GraphNodesTableAnnotationComposer,
      $$GraphNodesTableCreateCompanionBuilder,
      $$GraphNodesTableUpdateCompanionBuilder,
      (
        GraphNodeRow,
        BaseReferences<_$AppDatabase, $GraphNodesTable, GraphNodeRow>,
      ),
      GraphNodeRow,
      PrefetchHooks Function()
    >;
typedef $$GraphEdgesTableCreateCompanionBuilder =
    GraphEdgesCompanion Function({
      required String fromId,
      required String toId,
      required String type,
      Value<int> rowid,
    });
typedef $$GraphEdgesTableUpdateCompanionBuilder =
    GraphEdgesCompanion Function({
      Value<String> fromId,
      Value<String> toId,
      Value<String> type,
      Value<int> rowid,
    });

class $$GraphEdgesTableFilterComposer
    extends Composer<_$AppDatabase, $GraphEdgesTable> {
  $$GraphEdgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fromId => $composableBuilder(
    column: $table.fromId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toId => $composableBuilder(
    column: $table.toId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GraphEdgesTableOrderingComposer
    extends Composer<_$AppDatabase, $GraphEdgesTable> {
  $$GraphEdgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fromId => $composableBuilder(
    column: $table.fromId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toId => $composableBuilder(
    column: $table.toId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GraphEdgesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GraphEdgesTable> {
  $$GraphEdgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fromId =>
      $composableBuilder(column: $table.fromId, builder: (column) => column);

  GeneratedColumn<String> get toId =>
      $composableBuilder(column: $table.toId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);
}

class $$GraphEdgesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GraphEdgesTable,
          GraphEdgeRow,
          $$GraphEdgesTableFilterComposer,
          $$GraphEdgesTableOrderingComposer,
          $$GraphEdgesTableAnnotationComposer,
          $$GraphEdgesTableCreateCompanionBuilder,
          $$GraphEdgesTableUpdateCompanionBuilder,
          (
            GraphEdgeRow,
            BaseReferences<_$AppDatabase, $GraphEdgesTable, GraphEdgeRow>,
          ),
          GraphEdgeRow,
          PrefetchHooks Function()
        > {
  $$GraphEdgesTableTableManager(_$AppDatabase db, $GraphEdgesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GraphEdgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GraphEdgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GraphEdgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fromId = const Value.absent(),
                Value<String> toId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GraphEdgesCompanion(
                fromId: fromId,
                toId: toId,
                type: type,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fromId,
                required String toId,
                required String type,
                Value<int> rowid = const Value.absent(),
              }) => GraphEdgesCompanion.insert(
                fromId: fromId,
                toId: toId,
                type: type,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GraphEdgesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GraphEdgesTable,
      GraphEdgeRow,
      $$GraphEdgesTableFilterComposer,
      $$GraphEdgesTableOrderingComposer,
      $$GraphEdgesTableAnnotationComposer,
      $$GraphEdgesTableCreateCompanionBuilder,
      $$GraphEdgesTableUpdateCompanionBuilder,
      (
        GraphEdgeRow,
        BaseReferences<_$AppDatabase, $GraphEdgesTable, GraphEdgeRow>,
      ),
      GraphEdgeRow,
      PrefetchHooks Function()
    >;
typedef $$LearningHistoriesTableCreateCompanionBuilder =
    LearningHistoriesCompanion Function({
      Value<int> id,
      required String conceptTag,
      Value<String?> parentConcept,
      Value<int> level,
      required bool correct,
      Value<String?> articleTitle,
      required DateTime occurredAt,
    });
typedef $$LearningHistoriesTableUpdateCompanionBuilder =
    LearningHistoriesCompanion Function({
      Value<int> id,
      Value<String> conceptTag,
      Value<String?> parentConcept,
      Value<int> level,
      Value<bool> correct,
      Value<String?> articleTitle,
      Value<DateTime> occurredAt,
    });

class $$LearningHistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $LearningHistoriesTable> {
  $$LearningHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conceptTag => $composableBuilder(
    column: $table.conceptTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentConcept => $composableBuilder(
    column: $table.parentConcept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LearningHistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LearningHistoriesTable> {
  $$LearningHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conceptTag => $composableBuilder(
    column: $table.conceptTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentConcept => $composableBuilder(
    column: $table.parentConcept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LearningHistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LearningHistoriesTable> {
  $$LearningHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conceptTag => $composableBuilder(
    column: $table.conceptTag,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentConcept => $composableBuilder(
    column: $table.parentConcept,
    builder: (column) => column,
  );

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<bool> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$LearningHistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LearningHistoriesTable,
          LearningHistoryRow,
          $$LearningHistoriesTableFilterComposer,
          $$LearningHistoriesTableOrderingComposer,
          $$LearningHistoriesTableAnnotationComposer,
          $$LearningHistoriesTableCreateCompanionBuilder,
          $$LearningHistoriesTableUpdateCompanionBuilder,
          (
            LearningHistoryRow,
            BaseReferences<
              _$AppDatabase,
              $LearningHistoriesTable,
              LearningHistoryRow
            >,
          ),
          LearningHistoryRow,
          PrefetchHooks Function()
        > {
  $$LearningHistoriesTableTableManager(
    _$AppDatabase db,
    $LearningHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningHistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningHistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> conceptTag = const Value.absent(),
                Value<String?> parentConcept = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<bool> correct = const Value.absent(),
                Value<String?> articleTitle = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
              }) => LearningHistoriesCompanion(
                id: id,
                conceptTag: conceptTag,
                parentConcept: parentConcept,
                level: level,
                correct: correct,
                articleTitle: articleTitle,
                occurredAt: occurredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String conceptTag,
                Value<String?> parentConcept = const Value.absent(),
                Value<int> level = const Value.absent(),
                required bool correct,
                Value<String?> articleTitle = const Value.absent(),
                required DateTime occurredAt,
              }) => LearningHistoriesCompanion.insert(
                id: id,
                conceptTag: conceptTag,
                parentConcept: parentConcept,
                level: level,
                correct: correct,
                articleTitle: articleTitle,
                occurredAt: occurredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LearningHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LearningHistoriesTable,
      LearningHistoryRow,
      $$LearningHistoriesTableFilterComposer,
      $$LearningHistoriesTableOrderingComposer,
      $$LearningHistoriesTableAnnotationComposer,
      $$LearningHistoriesTableCreateCompanionBuilder,
      $$LearningHistoriesTableUpdateCompanionBuilder,
      (
        LearningHistoryRow,
        BaseReferences<
          _$AppDatabase,
          $LearningHistoriesTable,
          LearningHistoryRow
        >,
      ),
      LearningHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$ArticlePreferencesTableCreateCompanionBuilder =
    ArticlePreferencesCompanion Function({
      required String keyword,
      Value<String?> category,
      Value<double> weight,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ArticlePreferencesTableUpdateCompanionBuilder =
    ArticlePreferencesCompanion Function({
      Value<String> keyword,
      Value<String?> category,
      Value<double> weight,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ArticlePreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticlePreferencesTable> {
  $$ArticlePreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArticlePreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticlePreferencesTable> {
  $$ArticlePreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArticlePreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticlePreferencesTable> {
  $$ArticlePreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ArticlePreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticlePreferencesTable,
          ArticlePreferenceRow,
          $$ArticlePreferencesTableFilterComposer,
          $$ArticlePreferencesTableOrderingComposer,
          $$ArticlePreferencesTableAnnotationComposer,
          $$ArticlePreferencesTableCreateCompanionBuilder,
          $$ArticlePreferencesTableUpdateCompanionBuilder,
          (
            ArticlePreferenceRow,
            BaseReferences<
              _$AppDatabase,
              $ArticlePreferencesTable,
              ArticlePreferenceRow
            >,
          ),
          ArticlePreferenceRow,
          PrefetchHooks Function()
        > {
  $$ArticlePreferencesTableTableManager(
    _$AppDatabase db,
    $ArticlePreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticlePreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticlePreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticlePreferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> keyword = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArticlePreferencesCompanion(
                keyword: keyword,
                category: category,
                weight: weight,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyword,
                Value<String?> category = const Value.absent(),
                Value<double> weight = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ArticlePreferencesCompanion.insert(
                keyword: keyword,
                category: category,
                weight: weight,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArticlePreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticlePreferencesTable,
      ArticlePreferenceRow,
      $$ArticlePreferencesTableFilterComposer,
      $$ArticlePreferencesTableOrderingComposer,
      $$ArticlePreferencesTableAnnotationComposer,
      $$ArticlePreferencesTableCreateCompanionBuilder,
      $$ArticlePreferencesTableUpdateCompanionBuilder,
      (
        ArticlePreferenceRow,
        BaseReferences<
          _$AppDatabase,
          $ArticlePreferencesTable,
          ArticlePreferenceRow
        >,
      ),
      ArticlePreferenceRow,
      PrefetchHooks Function()
    >;
typedef $$AppliedScrapsTableCreateCompanionBuilder =
    AppliedScrapsCompanion Function({
      Value<int> id,
      required String articleTitle,
      Value<int> nodeCount,
      required DateTime appliedAt,
    });
typedef $$AppliedScrapsTableUpdateCompanionBuilder =
    AppliedScrapsCompanion Function({
      Value<int> id,
      Value<String> articleTitle,
      Value<int> nodeCount,
      Value<DateTime> appliedAt,
    });

class $$AppliedScrapsTableFilterComposer
    extends Composer<_$AppDatabase, $AppliedScrapsTable> {
  $$AppliedScrapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nodeCount => $composableBuilder(
    column: $table.nodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppliedScrapsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppliedScrapsTable> {
  $$AppliedScrapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nodeCount => $composableBuilder(
    column: $table.nodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppliedScrapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppliedScrapsTable> {
  $$AppliedScrapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get articleTitle => $composableBuilder(
    column: $table.articleTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nodeCount =>
      $composableBuilder(column: $table.nodeCount, builder: (column) => column);

  GeneratedColumn<DateTime> get appliedAt =>
      $composableBuilder(column: $table.appliedAt, builder: (column) => column);
}

class $$AppliedScrapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppliedScrapsTable,
          AppliedScrapRow,
          $$AppliedScrapsTableFilterComposer,
          $$AppliedScrapsTableOrderingComposer,
          $$AppliedScrapsTableAnnotationComposer,
          $$AppliedScrapsTableCreateCompanionBuilder,
          $$AppliedScrapsTableUpdateCompanionBuilder,
          (
            AppliedScrapRow,
            BaseReferences<_$AppDatabase, $AppliedScrapsTable, AppliedScrapRow>,
          ),
          AppliedScrapRow,
          PrefetchHooks Function()
        > {
  $$AppliedScrapsTableTableManager(_$AppDatabase db, $AppliedScrapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppliedScrapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppliedScrapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppliedScrapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> articleTitle = const Value.absent(),
                Value<int> nodeCount = const Value.absent(),
                Value<DateTime> appliedAt = const Value.absent(),
              }) => AppliedScrapsCompanion(
                id: id,
                articleTitle: articleTitle,
                nodeCount: nodeCount,
                appliedAt: appliedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String articleTitle,
                Value<int> nodeCount = const Value.absent(),
                required DateTime appliedAt,
              }) => AppliedScrapsCompanion.insert(
                id: id,
                articleTitle: articleTitle,
                nodeCount: nodeCount,
                appliedAt: appliedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppliedScrapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppliedScrapsTable,
      AppliedScrapRow,
      $$AppliedScrapsTableFilterComposer,
      $$AppliedScrapsTableOrderingComposer,
      $$AppliedScrapsTableAnnotationComposer,
      $$AppliedScrapsTableCreateCompanionBuilder,
      $$AppliedScrapsTableUpdateCompanionBuilder,
      (
        AppliedScrapRow,
        BaseReferences<_$AppDatabase, $AppliedScrapsTable, AppliedScrapRow>,
      ),
      AppliedScrapRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GraphNodesTableTableManager get graphNodes =>
      $$GraphNodesTableTableManager(_db, _db.graphNodes);
  $$GraphEdgesTableTableManager get graphEdges =>
      $$GraphEdgesTableTableManager(_db, _db.graphEdges);
  $$LearningHistoriesTableTableManager get learningHistories =>
      $$LearningHistoriesTableTableManager(_db, _db.learningHistories);
  $$ArticlePreferencesTableTableManager get articlePreferences =>
      $$ArticlePreferencesTableTableManager(_db, _db.articlePreferences);
  $$AppliedScrapsTableTableManager get appliedScraps =>
      $$AppliedScrapsTableTableManager(_db, _db.appliedScraps);
}
