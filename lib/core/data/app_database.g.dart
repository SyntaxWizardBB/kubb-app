// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PlayersTable extends Players with TableInfo<$PlayersTable, Player> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayersTable(this.attachedDatabase, [this._alias]);
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<String> avatarColor = GeneratedColumn<String>(
    'avatar_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    deviceId,
    avatarColor,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'players';
  @override
  VerificationContext validateIntegrity(
    Insertable<Player> instance, {
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
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Player map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Player(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_color'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlayersTable createAlias(String alias) {
    return $PlayersTable(attachedDatabase, alias);
  }
}

class Player extends DataClass implements Insertable<Player> {
  final String id;
  final String name;
  final String deviceId;
  final String? avatarColor;
  final DateTime createdAt;
  const Player({
    required this.id,
    required this.name,
    required this.deviceId,
    this.avatarColor,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || avatarColor != null) {
      map['avatar_color'] = Variable<String>(avatarColor);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PlayersCompanion toCompanion(bool nullToAbsent) {
    return PlayersCompanion(
      id: Value(id),
      name: Value(name),
      deviceId: Value(deviceId),
      avatarColor: avatarColor == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarColor),
      createdAt: Value(createdAt),
    );
  }

  factory Player.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Player(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      avatarColor: serializer.fromJson<String?>(json['avatarColor']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'deviceId': serializer.toJson<String>(deviceId),
      'avatarColor': serializer.toJson<String?>(avatarColor),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Player copyWith({
    String? id,
    String? name,
    String? deviceId,
    Value<String?> avatarColor = const Value.absent(),
    DateTime? createdAt,
  }) => Player(
    id: id ?? this.id,
    name: name ?? this.name,
    deviceId: deviceId ?? this.deviceId,
    avatarColor: avatarColor.present ? avatarColor.value : this.avatarColor,
    createdAt: createdAt ?? this.createdAt,
  );
  Player copyWithCompanion(PlayersCompanion data) {
    return Player(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Player(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceId: $deviceId, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, deviceId, avatarColor, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Player &&
          other.id == this.id &&
          other.name == this.name &&
          other.deviceId == this.deviceId &&
          other.avatarColor == this.avatarColor &&
          other.createdAt == this.createdAt);
}

class PlayersCompanion extends UpdateCompanion<Player> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> deviceId;
  final Value<String?> avatarColor;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PlayersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayersCompanion.insert({
    required String id,
    required String name,
    required String deviceId,
    this.avatarColor = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       deviceId = Value(deviceId),
       createdAt = Value(createdAt);
  static Insertable<Player> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? deviceId,
    Expression<String>? avatarColor,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (deviceId != null) 'device_id': deviceId,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? deviceId,
    Value<String?>? avatarColor,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PlayersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt ?? this.createdAt,
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
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<String>(avatarColor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceId: $deviceId, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playerIdMeta = const VerificationMeta(
    'playerId',
  );
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
    'player_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES players (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sniper'),
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<double> distanceMeters = GeneratedColumn<double>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _throwTargetMeta = const VerificationMeta(
    'throwTarget',
  );
  @override
  late final GeneratedColumn<int> throwTarget = GeneratedColumn<int>(
    'throw_target',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finFieldMeta = const VerificationMeta(
    'finField',
  );
  @override
  late final GeneratedColumn<int> finField = GeneratedColumn<int>(
    'fin_field',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finBaseMeta = const VerificationMeta(
    'finBase',
  );
  @override
  late final GeneratedColumn<int> finBase = GeneratedColumn<int>(
    'fin_base',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playerId,
    kind,
    mode,
    distanceMeters,
    throwTarget,
    finField,
    finBase,
    status,
    startedAt,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('player_id')) {
      context.handle(
        _playerIdMeta,
        playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distanceMetersMeta);
    }
    if (data.containsKey('throw_target')) {
      context.handle(
        _throwTargetMeta,
        throwTarget.isAcceptableOrUnknown(
          data['throw_target']!,
          _throwTargetMeta,
        ),
      );
    }
    if (data.containsKey('fin_field')) {
      context.handle(
        _finFieldMeta,
        finField.isAcceptableOrUnknown(data['fin_field']!, _finFieldMeta),
      );
    }
    if (data.containsKey('fin_base')) {
      context.handle(
        _finBaseMeta,
        finBase.isAcceptableOrUnknown(data['fin_base']!, _finBaseMeta),
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
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      playerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}player_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_meters'],
      )!,
      throwTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}throw_target'],
      ),
      finField: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fin_field'],
      ),
      finBase: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fin_base'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final String playerId;
  final String kind;
  final String mode;
  final double distanceMeters;
  final int? throwTarget;
  final int? finField;
  final int? finBase;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  const Session({
    required this.id,
    required this.playerId,
    required this.kind,
    required this.mode,
    required this.distanceMeters,
    this.throwTarget,
    this.finField,
    this.finBase,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['player_id'] = Variable<String>(playerId);
    map['kind'] = Variable<String>(kind);
    map['mode'] = Variable<String>(mode);
    map['distance_meters'] = Variable<double>(distanceMeters);
    if (!nullToAbsent || throwTarget != null) {
      map['throw_target'] = Variable<int>(throwTarget);
    }
    if (!nullToAbsent || finField != null) {
      map['fin_field'] = Variable<int>(finField);
    }
    if (!nullToAbsent || finBase != null) {
      map['fin_base'] = Variable<int>(finBase);
    }
    map['status'] = Variable<String>(status);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      playerId: Value(playerId),
      kind: Value(kind),
      mode: Value(mode),
      distanceMeters: Value(distanceMeters),
      throwTarget: throwTarget == null && nullToAbsent
          ? const Value.absent()
          : Value(throwTarget),
      finField: finField == null && nullToAbsent
          ? const Value.absent()
          : Value(finField),
      finBase: finBase == null && nullToAbsent
          ? const Value.absent()
          : Value(finBase),
      status: Value(status),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      playerId: serializer.fromJson<String>(json['playerId']),
      kind: serializer.fromJson<String>(json['kind']),
      mode: serializer.fromJson<String>(json['mode']),
      distanceMeters: serializer.fromJson<double>(json['distanceMeters']),
      throwTarget: serializer.fromJson<int?>(json['throwTarget']),
      finField: serializer.fromJson<int?>(json['finField']),
      finBase: serializer.fromJson<int?>(json['finBase']),
      status: serializer.fromJson<String>(json['status']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'playerId': serializer.toJson<String>(playerId),
      'kind': serializer.toJson<String>(kind),
      'mode': serializer.toJson<String>(mode),
      'distanceMeters': serializer.toJson<double>(distanceMeters),
      'throwTarget': serializer.toJson<int?>(throwTarget),
      'finField': serializer.toJson<int?>(finField),
      'finBase': serializer.toJson<int?>(finBase),
      'status': serializer.toJson<String>(status),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  Session copyWith({
    String? id,
    String? playerId,
    String? kind,
    String? mode,
    double? distanceMeters,
    Value<int?> throwTarget = const Value.absent(),
    Value<int?> finField = const Value.absent(),
    Value<int?> finBase = const Value.absent(),
    String? status,
    DateTime? startedAt,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => Session(
    id: id ?? this.id,
    playerId: playerId ?? this.playerId,
    kind: kind ?? this.kind,
    mode: mode ?? this.mode,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    throwTarget: throwTarget.present ? throwTarget.value : this.throwTarget,
    finField: finField.present ? finField.value : this.finField,
    finBase: finBase.present ? finBase.value : this.finBase,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      kind: data.kind.present ? data.kind.value : this.kind,
      mode: data.mode.present ? data.mode.value : this.mode,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      throwTarget: data.throwTarget.present
          ? data.throwTarget.value
          : this.throwTarget,
      finField: data.finField.present ? data.finField.value : this.finField,
      finBase: data.finBase.present ? data.finBase.value : this.finBase,
      status: data.status.present ? data.status.value : this.status,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('kind: $kind, ')
          ..write('mode: $mode, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('throwTarget: $throwTarget, ')
          ..write('finField: $finField, ')
          ..write('finBase: $finBase, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playerId,
    kind,
    mode,
    distanceMeters,
    throwTarget,
    finField,
    finBase,
    status,
    startedAt,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.playerId == this.playerId &&
          other.kind == this.kind &&
          other.mode == this.mode &&
          other.distanceMeters == this.distanceMeters &&
          other.throwTarget == this.throwTarget &&
          other.finField == this.finField &&
          other.finBase == this.finBase &&
          other.status == this.status &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> playerId;
  final Value<String> kind;
  final Value<String> mode;
  final Value<double> distanceMeters;
  final Value<int?> throwTarget;
  final Value<int?> finField;
  final Value<int?> finBase;
  final Value<String> status;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.playerId = const Value.absent(),
    this.kind = const Value.absent(),
    this.mode = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.throwTarget = const Value.absent(),
    this.finField = const Value.absent(),
    this.finBase = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String playerId,
    required String kind,
    this.mode = const Value.absent(),
    required double distanceMeters,
    this.throwTarget = const Value.absent(),
    this.finField = const Value.absent(),
    this.finBase = const Value.absent(),
    required String status,
    required DateTime startedAt,
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       playerId = Value(playerId),
       kind = Value(kind),
       distanceMeters = Value(distanceMeters),
       status = Value(status),
       startedAt = Value(startedAt);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? playerId,
    Expression<String>? kind,
    Expression<String>? mode,
    Expression<double>? distanceMeters,
    Expression<int>? throwTarget,
    Expression<int>? finField,
    Expression<int>? finBase,
    Expression<String>? status,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playerId != null) 'player_id': playerId,
      if (kind != null) 'kind': kind,
      if (mode != null) 'mode': mode,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (throwTarget != null) 'throw_target': throwTarget,
      if (finField != null) 'fin_field': finField,
      if (finBase != null) 'fin_base': finBase,
      if (status != null) 'status': status,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? playerId,
    Value<String>? kind,
    Value<String>? mode,
    Value<double>? distanceMeters,
    Value<int?>? throwTarget,
    Value<int?>? finField,
    Value<int?>? finBase,
    Value<String>? status,
    Value<DateTime>? startedAt,
    Value<DateTime?>? completedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      kind: kind ?? this.kind,
      mode: mode ?? this.mode,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      throwTarget: throwTarget ?? this.throwTarget,
      finField: finField ?? this.finField,
      finBase: finBase ?? this.finBase,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<double>(distanceMeters.value);
    }
    if (throwTarget.present) {
      map['throw_target'] = Variable<int>(throwTarget.value);
    }
    if (finField.present) {
      map['fin_field'] = Variable<int>(finField.value);
    }
    if (finBase.present) {
      map['fin_base'] = Variable<int>(finBase.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('kind: $kind, ')
          ..write('mode: $mode, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('throwTarget: $throwTarget, ')
          ..write('finField: $finField, ')
          ..write('finBase: $finBase, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionEventsTable extends SessionEvents
    with TableInfo<$SessionEventsTable, SessionEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctedAtMeta = const VerificationMeta(
    'correctedAt',
  );
  @override
  late final GeneratedColumn<DateTime> correctedAt = GeneratedColumn<DateTime>(
    'corrected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    kind,
    createdAt,
    correctedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('corrected_at')) {
      context.handle(
        _correctedAtMeta,
        correctedAt.isAcceptableOrUnknown(
          data['corrected_at']!,
          _correctedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      correctedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}corrected_at'],
      ),
    );
  }

  @override
  $SessionEventsTable createAlias(String alias) {
    return $SessionEventsTable(attachedDatabase, alias);
  }
}

class SessionEvent extends DataClass implements Insertable<SessionEvent> {
  final String id;
  final String sessionId;
  final String kind;
  final DateTime createdAt;
  final DateTime? correctedAt;
  const SessionEvent({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.createdAt,
    this.correctedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['kind'] = Variable<String>(kind);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || correctedAt != null) {
      map['corrected_at'] = Variable<DateTime>(correctedAt);
    }
    return map;
  }

  SessionEventsCompanion toCompanion(bool nullToAbsent) {
    return SessionEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      kind: Value(kind),
      createdAt: Value(createdAt),
      correctedAt: correctedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedAt),
    );
  }

  factory SessionEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionEvent(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      kind: serializer.fromJson<String>(json['kind']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      correctedAt: serializer.fromJson<DateTime?>(json['correctedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'kind': serializer.toJson<String>(kind),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'correctedAt': serializer.toJson<DateTime?>(correctedAt),
    };
  }

  SessionEvent copyWith({
    String? id,
    String? sessionId,
    String? kind,
    DateTime? createdAt,
    Value<DateTime?> correctedAt = const Value.absent(),
  }) => SessionEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
    correctedAt: correctedAt.present ? correctedAt.value : this.correctedAt,
  );
  SessionEvent copyWithCompanion(SessionEventsCompanion data) {
    return SessionEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      correctedAt: data.correctedAt.present
          ? data.correctedAt.value
          : this.correctedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('correctedAt: $correctedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, kind, createdAt, correctedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt &&
          other.correctedAt == this.correctedAt);
}

class SessionEventsCompanion extends UpdateCompanion<SessionEvent> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> kind;
  final Value<DateTime> createdAt;
  final Value<DateTime?> correctedAt;
  final Value<int> rowid;
  const SessionEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionEventsCompanion.insert({
    required String id,
    required String sessionId,
    required String kind,
    required DateTime createdAt,
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<SessionEvent> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? kind,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? correctedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
      if (correctedAt != null) 'corrected_at': correctedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? kind,
    Value<DateTime>? createdAt,
    Value<DateTime?>? correctedAt,
    Value<int>? rowid,
  }) {
    return SessionEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      correctedAt: correctedAt ?? this.correctedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (correctedAt.present) {
      map['corrected_at'] = Variable<DateTime>(correctedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('correctedAt: $correctedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTableTable extends AppSettingsTable
    with TableInfo<$AppSettingsTableTable, AppSettingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsTableData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTableTable createAlias(String alias) {
    return $AppSettingsTableTable(attachedDatabase, alias);
  }
}

class AppSettingsTableData extends DataClass
    implements Insertable<AppSettingsTableData> {
  final String key;
  final String value;
  const AppSettingsTableData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory AppSettingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsTableData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSettingsTableData copyWith({String? key, String? value}) =>
      AppSettingsTableData(key: key ?? this.key, value: value ?? this.value);
  AppSettingsTableData copyWithCompanion(AppSettingsTableCompanion data) {
    return AppSettingsTableData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsTableData &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsTableCompanion extends UpdateCompanion<AppSettingsTableData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSettingsTableData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinisseurStickEventsTable extends FinisseurStickEvents
    with TableInfo<$FinisseurStickEventsTable, FinisseurStickEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinisseurStickEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _stickIndexMeta = const VerificationMeta(
    'stickIndex',
  );
  @override
  late final GeneratedColumn<int> stickIndex = GeneratedColumn<int>(
    'stick_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldKubbsHitMeta = const VerificationMeta(
    'fieldKubbsHit',
  );
  @override
  late final GeneratedColumn<int> fieldKubbsHit = GeneratedColumn<int>(
    'field_kubbs_hit',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _eightMHitMeta = const VerificationMeta(
    'eightMHit',
  );
  @override
  late final GeneratedColumn<bool> eightMHit = GeneratedColumn<bool>(
    'eight_m_hit',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("eight_m_hit" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _heliThrowMeta = const VerificationMeta(
    'heliThrow',
  );
  @override
  late final GeneratedColumn<bool> heliThrow = GeneratedColumn<bool>(
    'heli_throw',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("heli_throw" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _kingHitMeta = const VerificationMeta(
    'kingHit',
  );
  @override
  late final GeneratedColumn<bool> kingHit = GeneratedColumn<bool>(
    'king_hit',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("king_hit" IN (0, 1))',
    ),
  );
  static const VerificationMeta _kingPositionMeta = const VerificationMeta(
    'kingPosition',
  );
  @override
  late final GeneratedColumn<String> kingPosition = GeneratedColumn<String>(
    'king_position',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _penaltyHits1Meta = const VerificationMeta(
    'penaltyHits1',
  );
  @override
  late final GeneratedColumn<int> penaltyHits1 = GeneratedColumn<int>(
    'penalty_hits1',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _penaltyHits2Meta = const VerificationMeta(
    'penaltyHits2',
  );
  @override
  late final GeneratedColumn<int> penaltyHits2 = GeneratedColumn<int>(
    'penalty_hits2',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    stickIndex,
    fieldKubbsHit,
    eightMHit,
    heliThrow,
    kingHit,
    kingPosition,
    penaltyHits1,
    penaltyHits2,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'finisseur_stick_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<FinisseurStickEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('stick_index')) {
      context.handle(
        _stickIndexMeta,
        stickIndex.isAcceptableOrUnknown(data['stick_index']!, _stickIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_stickIndexMeta);
    }
    if (data.containsKey('field_kubbs_hit')) {
      context.handle(
        _fieldKubbsHitMeta,
        fieldKubbsHit.isAcceptableOrUnknown(
          data['field_kubbs_hit']!,
          _fieldKubbsHitMeta,
        ),
      );
    }
    if (data.containsKey('eight_m_hit')) {
      context.handle(
        _eightMHitMeta,
        eightMHit.isAcceptableOrUnknown(data['eight_m_hit']!, _eightMHitMeta),
      );
    }
    if (data.containsKey('heli_throw')) {
      context.handle(
        _heliThrowMeta,
        heliThrow.isAcceptableOrUnknown(data['heli_throw']!, _heliThrowMeta),
      );
    }
    if (data.containsKey('king_hit')) {
      context.handle(
        _kingHitMeta,
        kingHit.isAcceptableOrUnknown(data['king_hit']!, _kingHitMeta),
      );
    }
    if (data.containsKey('king_position')) {
      context.handle(
        _kingPositionMeta,
        kingPosition.isAcceptableOrUnknown(
          data['king_position']!,
          _kingPositionMeta,
        ),
      );
    }
    if (data.containsKey('penalty_hits1')) {
      context.handle(
        _penaltyHits1Meta,
        penaltyHits1.isAcceptableOrUnknown(
          data['penalty_hits1']!,
          _penaltyHits1Meta,
        ),
      );
    }
    if (data.containsKey('penalty_hits2')) {
      context.handle(
        _penaltyHits2Meta,
        penaltyHits2.isAcceptableOrUnknown(
          data['penalty_hits2']!,
          _penaltyHits2Meta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FinisseurStickEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinisseurStickEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      stickIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stick_index'],
      )!,
      fieldKubbsHit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}field_kubbs_hit'],
      )!,
      eightMHit: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}eight_m_hit'],
      )!,
      heliThrow: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}heli_throw'],
      )!,
      kingHit: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}king_hit'],
      ),
      kingPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}king_position'],
      ),
      penaltyHits1: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}penalty_hits1'],
      )!,
      penaltyHits2: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}penalty_hits2'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FinisseurStickEventsTable createAlias(String alias) {
    return $FinisseurStickEventsTable(attachedDatabase, alias);
  }
}

class FinisseurStickEvent extends DataClass
    implements Insertable<FinisseurStickEvent> {
  final String id;
  final String sessionId;
  final int stickIndex;
  final int fieldKubbsHit;
  final bool eightMHit;
  final bool heliThrow;
  final bool? kingHit;
  final String? kingPosition;
  final int penaltyHits1;
  final int penaltyHits2;
  final DateTime createdAt;
  const FinisseurStickEvent({
    required this.id,
    required this.sessionId,
    required this.stickIndex,
    required this.fieldKubbsHit,
    required this.eightMHit,
    required this.heliThrow,
    this.kingHit,
    this.kingPosition,
    required this.penaltyHits1,
    required this.penaltyHits2,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['stick_index'] = Variable<int>(stickIndex);
    map['field_kubbs_hit'] = Variable<int>(fieldKubbsHit);
    map['eight_m_hit'] = Variable<bool>(eightMHit);
    map['heli_throw'] = Variable<bool>(heliThrow);
    if (!nullToAbsent || kingHit != null) {
      map['king_hit'] = Variable<bool>(kingHit);
    }
    if (!nullToAbsent || kingPosition != null) {
      map['king_position'] = Variable<String>(kingPosition);
    }
    map['penalty_hits1'] = Variable<int>(penaltyHits1);
    map['penalty_hits2'] = Variable<int>(penaltyHits2);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FinisseurStickEventsCompanion toCompanion(bool nullToAbsent) {
    return FinisseurStickEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      stickIndex: Value(stickIndex),
      fieldKubbsHit: Value(fieldKubbsHit),
      eightMHit: Value(eightMHit),
      heliThrow: Value(heliThrow),
      kingHit: kingHit == null && nullToAbsent
          ? const Value.absent()
          : Value(kingHit),
      kingPosition: kingPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(kingPosition),
      penaltyHits1: Value(penaltyHits1),
      penaltyHits2: Value(penaltyHits2),
      createdAt: Value(createdAt),
    );
  }

  factory FinisseurStickEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinisseurStickEvent(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      stickIndex: serializer.fromJson<int>(json['stickIndex']),
      fieldKubbsHit: serializer.fromJson<int>(json['fieldKubbsHit']),
      eightMHit: serializer.fromJson<bool>(json['eightMHit']),
      heliThrow: serializer.fromJson<bool>(json['heliThrow']),
      kingHit: serializer.fromJson<bool?>(json['kingHit']),
      kingPosition: serializer.fromJson<String?>(json['kingPosition']),
      penaltyHits1: serializer.fromJson<int>(json['penaltyHits1']),
      penaltyHits2: serializer.fromJson<int>(json['penaltyHits2']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'stickIndex': serializer.toJson<int>(stickIndex),
      'fieldKubbsHit': serializer.toJson<int>(fieldKubbsHit),
      'eightMHit': serializer.toJson<bool>(eightMHit),
      'heliThrow': serializer.toJson<bool>(heliThrow),
      'kingHit': serializer.toJson<bool?>(kingHit),
      'kingPosition': serializer.toJson<String?>(kingPosition),
      'penaltyHits1': serializer.toJson<int>(penaltyHits1),
      'penaltyHits2': serializer.toJson<int>(penaltyHits2),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FinisseurStickEvent copyWith({
    String? id,
    String? sessionId,
    int? stickIndex,
    int? fieldKubbsHit,
    bool? eightMHit,
    bool? heliThrow,
    Value<bool?> kingHit = const Value.absent(),
    Value<String?> kingPosition = const Value.absent(),
    int? penaltyHits1,
    int? penaltyHits2,
    DateTime? createdAt,
  }) => FinisseurStickEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    stickIndex: stickIndex ?? this.stickIndex,
    fieldKubbsHit: fieldKubbsHit ?? this.fieldKubbsHit,
    eightMHit: eightMHit ?? this.eightMHit,
    heliThrow: heliThrow ?? this.heliThrow,
    kingHit: kingHit.present ? kingHit.value : this.kingHit,
    kingPosition: kingPosition.present ? kingPosition.value : this.kingPosition,
    penaltyHits1: penaltyHits1 ?? this.penaltyHits1,
    penaltyHits2: penaltyHits2 ?? this.penaltyHits2,
    createdAt: createdAt ?? this.createdAt,
  );
  FinisseurStickEvent copyWithCompanion(FinisseurStickEventsCompanion data) {
    return FinisseurStickEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      stickIndex: data.stickIndex.present
          ? data.stickIndex.value
          : this.stickIndex,
      fieldKubbsHit: data.fieldKubbsHit.present
          ? data.fieldKubbsHit.value
          : this.fieldKubbsHit,
      eightMHit: data.eightMHit.present ? data.eightMHit.value : this.eightMHit,
      heliThrow: data.heliThrow.present ? data.heliThrow.value : this.heliThrow,
      kingHit: data.kingHit.present ? data.kingHit.value : this.kingHit,
      kingPosition: data.kingPosition.present
          ? data.kingPosition.value
          : this.kingPosition,
      penaltyHits1: data.penaltyHits1.present
          ? data.penaltyHits1.value
          : this.penaltyHits1,
      penaltyHits2: data.penaltyHits2.present
          ? data.penaltyHits2.value
          : this.penaltyHits2,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinisseurStickEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('stickIndex: $stickIndex, ')
          ..write('fieldKubbsHit: $fieldKubbsHit, ')
          ..write('eightMHit: $eightMHit, ')
          ..write('heliThrow: $heliThrow, ')
          ..write('kingHit: $kingHit, ')
          ..write('kingPosition: $kingPosition, ')
          ..write('penaltyHits1: $penaltyHits1, ')
          ..write('penaltyHits2: $penaltyHits2, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    stickIndex,
    fieldKubbsHit,
    eightMHit,
    heliThrow,
    kingHit,
    kingPosition,
    penaltyHits1,
    penaltyHits2,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinisseurStickEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.stickIndex == this.stickIndex &&
          other.fieldKubbsHit == this.fieldKubbsHit &&
          other.eightMHit == this.eightMHit &&
          other.heliThrow == this.heliThrow &&
          other.kingHit == this.kingHit &&
          other.kingPosition == this.kingPosition &&
          other.penaltyHits1 == this.penaltyHits1 &&
          other.penaltyHits2 == this.penaltyHits2 &&
          other.createdAt == this.createdAt);
}

class FinisseurStickEventsCompanion
    extends UpdateCompanion<FinisseurStickEvent> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<int> stickIndex;
  final Value<int> fieldKubbsHit;
  final Value<bool> eightMHit;
  final Value<bool> heliThrow;
  final Value<bool?> kingHit;
  final Value<String?> kingPosition;
  final Value<int> penaltyHits1;
  final Value<int> penaltyHits2;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FinisseurStickEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.stickIndex = const Value.absent(),
    this.fieldKubbsHit = const Value.absent(),
    this.eightMHit = const Value.absent(),
    this.heliThrow = const Value.absent(),
    this.kingHit = const Value.absent(),
    this.kingPosition = const Value.absent(),
    this.penaltyHits1 = const Value.absent(),
    this.penaltyHits2 = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinisseurStickEventsCompanion.insert({
    required String id,
    required String sessionId,
    required int stickIndex,
    this.fieldKubbsHit = const Value.absent(),
    this.eightMHit = const Value.absent(),
    this.heliThrow = const Value.absent(),
    this.kingHit = const Value.absent(),
    this.kingPosition = const Value.absent(),
    this.penaltyHits1 = const Value.absent(),
    this.penaltyHits2 = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       stickIndex = Value(stickIndex),
       createdAt = Value(createdAt);
  static Insertable<FinisseurStickEvent> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<int>? stickIndex,
    Expression<int>? fieldKubbsHit,
    Expression<bool>? eightMHit,
    Expression<bool>? heliThrow,
    Expression<bool>? kingHit,
    Expression<String>? kingPosition,
    Expression<int>? penaltyHits1,
    Expression<int>? penaltyHits2,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (stickIndex != null) 'stick_index': stickIndex,
      if (fieldKubbsHit != null) 'field_kubbs_hit': fieldKubbsHit,
      if (eightMHit != null) 'eight_m_hit': eightMHit,
      if (heliThrow != null) 'heli_throw': heliThrow,
      if (kingHit != null) 'king_hit': kingHit,
      if (kingPosition != null) 'king_position': kingPosition,
      if (penaltyHits1 != null) 'penalty_hits1': penaltyHits1,
      if (penaltyHits2 != null) 'penalty_hits2': penaltyHits2,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinisseurStickEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<int>? stickIndex,
    Value<int>? fieldKubbsHit,
    Value<bool>? eightMHit,
    Value<bool>? heliThrow,
    Value<bool?>? kingHit,
    Value<String?>? kingPosition,
    Value<int>? penaltyHits1,
    Value<int>? penaltyHits2,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return FinisseurStickEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      stickIndex: stickIndex ?? this.stickIndex,
      fieldKubbsHit: fieldKubbsHit ?? this.fieldKubbsHit,
      eightMHit: eightMHit ?? this.eightMHit,
      heliThrow: heliThrow ?? this.heliThrow,
      kingHit: kingHit ?? this.kingHit,
      kingPosition: kingPosition ?? this.kingPosition,
      penaltyHits1: penaltyHits1 ?? this.penaltyHits1,
      penaltyHits2: penaltyHits2 ?? this.penaltyHits2,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (stickIndex.present) {
      map['stick_index'] = Variable<int>(stickIndex.value);
    }
    if (fieldKubbsHit.present) {
      map['field_kubbs_hit'] = Variable<int>(fieldKubbsHit.value);
    }
    if (eightMHit.present) {
      map['eight_m_hit'] = Variable<bool>(eightMHit.value);
    }
    if (heliThrow.present) {
      map['heli_throw'] = Variable<bool>(heliThrow.value);
    }
    if (kingHit.present) {
      map['king_hit'] = Variable<bool>(kingHit.value);
    }
    if (kingPosition.present) {
      map['king_position'] = Variable<String>(kingPosition.value);
    }
    if (penaltyHits1.present) {
      map['penalty_hits1'] = Variable<int>(penaltyHits1.value);
    }
    if (penaltyHits2.present) {
      map['penalty_hits2'] = Variable<int>(penaltyHits2.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinisseurStickEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('stickIndex: $stickIndex, ')
          ..write('fieldKubbsHit: $fieldKubbsHit, ')
          ..write('eightMHit: $eightMHit, ')
          ..write('heliThrow: $heliThrow, ')
          ..write('kingHit: $kingHit, ')
          ..write('kingPosition: $kingPosition, ')
          ..write('penaltyHits1: $penaltyHits1, ')
          ..write('penaltyHits2: $penaltyHits2, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedAuthSessionTable extends CachedAuthSession
    with TableInfo<$CachedAuthSessionTable, CachedAuthSessionData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedAuthSessionTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('singleton'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<String> avatarColor = GeneratedColumn<String>(
    'avatar_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshAfterMeta = const VerificationMeta(
    'refreshAfter',
  );
  @override
  late final GeneratedColumn<DateTime> refreshAfter = GeneratedColumn<DateTime>(
    'refresh_after',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    kind,
    displayName,
    avatarColor,
    expiresAt,
    refreshAfter,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_auth_session';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedAuthSessionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('refresh_after')) {
      context.handle(
        _refreshAfterMeta,
        refreshAfter.isAcceptableOrUnknown(
          data['refresh_after']!,
          _refreshAfterMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshAfterMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  CachedAuthSessionData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedAuthSessionData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_color'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
      refreshAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refresh_after'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedAuthSessionTable createAlias(String alias) {
    return $CachedAuthSessionTable(attachedDatabase, alias);
  }
}

class CachedAuthSessionData extends DataClass
    implements Insertable<CachedAuthSessionData> {
  final String id;
  final String userId;
  final String kind;
  final String displayName;
  final String? avatarColor;
  final DateTime expiresAt;
  final DateTime refreshAfter;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CachedAuthSessionData({
    required this.id,
    required this.userId,
    required this.kind,
    required this.displayName,
    this.avatarColor,
    required this.expiresAt,
    required this.refreshAfter,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['kind'] = Variable<String>(kind);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarColor != null) {
      map['avatar_color'] = Variable<String>(avatarColor);
    }
    map['expires_at'] = Variable<DateTime>(expiresAt);
    map['refresh_after'] = Variable<DateTime>(refreshAfter);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedAuthSessionCompanion toCompanion(bool nullToAbsent) {
    return CachedAuthSessionCompanion(
      id: Value(id),
      userId: Value(userId),
      kind: Value(kind),
      displayName: Value(displayName),
      avatarColor: avatarColor == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarColor),
      expiresAt: Value(expiresAt),
      refreshAfter: Value(refreshAfter),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedAuthSessionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedAuthSessionData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      kind: serializer.fromJson<String>(json['kind']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarColor: serializer.fromJson<String?>(json['avatarColor']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      refreshAfter: serializer.fromJson<DateTime>(json['refreshAfter']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'kind': serializer.toJson<String>(kind),
      'displayName': serializer.toJson<String>(displayName),
      'avatarColor': serializer.toJson<String?>(avatarColor),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'refreshAfter': serializer.toJson<DateTime>(refreshAfter),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedAuthSessionData copyWith({
    String? id,
    String? userId,
    String? kind,
    String? displayName,
    Value<String?> avatarColor = const Value.absent(),
    DateTime? expiresAt,
    DateTime? refreshAfter,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CachedAuthSessionData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    kind: kind ?? this.kind,
    displayName: displayName ?? this.displayName,
    avatarColor: avatarColor.present ? avatarColor.value : this.avatarColor,
    expiresAt: expiresAt ?? this.expiresAt,
    refreshAfter: refreshAfter ?? this.refreshAfter,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedAuthSessionData copyWithCompanion(CachedAuthSessionCompanion data) {
    return CachedAuthSessionData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      kind: data.kind.present ? data.kind.value : this.kind,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      refreshAfter: data.refreshAfter.present
          ? data.refreshAfter.value
          : this.refreshAfter,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedAuthSessionData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('displayName: $displayName, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('refreshAfter: $refreshAfter, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    kind,
    displayName,
    avatarColor,
    expiresAt,
    refreshAfter,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedAuthSessionData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.kind == this.kind &&
          other.displayName == this.displayName &&
          other.avatarColor == this.avatarColor &&
          other.expiresAt == this.expiresAt &&
          other.refreshAfter == this.refreshAfter &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CachedAuthSessionCompanion
    extends UpdateCompanion<CachedAuthSessionData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> kind;
  final Value<String> displayName;
  final Value<String?> avatarColor;
  final Value<DateTime> expiresAt;
  final Value<DateTime> refreshAfter;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedAuthSessionCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.kind = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.refreshAfter = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedAuthSessionCompanion.insert({
    this.id = const Value.absent(),
    required String userId,
    required String kind,
    required String displayName,
    this.avatarColor = const Value.absent(),
    required DateTime expiresAt,
    required DateTime refreshAfter,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       kind = Value(kind),
       displayName = Value(displayName),
       expiresAt = Value(expiresAt),
       refreshAfter = Value(refreshAfter),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CachedAuthSessionData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? kind,
    Expression<String>? displayName,
    Expression<String>? avatarColor,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? refreshAfter,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (kind != null) 'kind': kind,
      if (displayName != null) 'display_name': displayName,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (refreshAfter != null) 'refresh_after': refreshAfter,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedAuthSessionCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? kind,
    Value<String>? displayName,
    Value<String?>? avatarColor,
    Value<DateTime>? expiresAt,
    Value<DateTime>? refreshAfter,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedAuthSessionCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      avatarColor: avatarColor ?? this.avatarColor,
      expiresAt: expiresAt ?? this.expiresAt,
      refreshAfter: refreshAfter ?? this.refreshAfter,
      createdAt: createdAt ?? this.createdAt,
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
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<String>(avatarColor.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (refreshAfter.present) {
      map['refresh_after'] = Variable<DateTime>(refreshAfter.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('CachedAuthSessionCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('displayName: $displayName, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('refreshAfter: $refreshAfter, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PlayersTable players = $PlayersTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SessionEventsTable sessionEvents = $SessionEventsTable(this);
  late final $AppSettingsTableTable appSettingsTable = $AppSettingsTableTable(
    this,
  );
  late final $FinisseurStickEventsTable finisseurStickEvents =
      $FinisseurStickEventsTable(this);
  late final $CachedAuthSessionTable cachedAuthSession =
      $CachedAuthSessionTable(this);
  late final PlayerDao playerDao = PlayerDao(this as AppDatabase);
  late final SessionDao sessionDao = SessionDao(this as AppDatabase);
  late final SessionEventDao sessionEventDao = SessionEventDao(
    this as AppDatabase,
  );
  late final AppSettingsDao appSettingsDao = AppSettingsDao(
    this as AppDatabase,
  );
  late final FinisseurStickEventDao finisseurStickEventDao =
      FinisseurStickEventDao(this as AppDatabase);
  late final CachedAuthSessionDao cachedAuthSessionDao = CachedAuthSessionDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    players,
    sessions,
    sessionEvents,
    appSettingsTable,
    finisseurStickEvents,
    cachedAuthSession,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('session_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('finisseur_stick_events', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PlayersTableCreateCompanionBuilder =
    PlayersCompanion Function({
      required String id,
      required String name,
      required String deviceId,
      Value<String?> avatarColor,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$PlayersTableUpdateCompanionBuilder =
    PlayersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> deviceId,
      Value<String?> avatarColor,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$PlayersTableReferences
    extends BaseReferences<_$AppDatabase, $PlayersTable, Player> {
  $$PlayersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: $_aliasNameGenerator(db.players.id, db.sessions.playerId),
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.playerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlayersTableFilterComposer
    extends Composer<_$AppDatabase, $PlayersTable> {
  $$PlayersTableFilterComposer({
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

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.playerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlayersTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayersTable> {
  $$PlayersTableOrderingComposer({
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

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayersTable> {
  $$PlayersTableAnnotationComposer({
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

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.playerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlayersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayersTable,
          Player,
          $$PlayersTableFilterComposer,
          $$PlayersTableOrderingComposer,
          $$PlayersTableAnnotationComposer,
          $$PlayersTableCreateCompanionBuilder,
          $$PlayersTableUpdateCompanionBuilder,
          (Player, $$PlayersTableReferences),
          Player,
          PrefetchHooks Function({bool sessionsRefs})
        > {
  $$PlayersTableTableManager(_$AppDatabase db, $PlayersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String?> avatarColor = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayersCompanion(
                id: id,
                name: name,
                deviceId: deviceId,
                avatarColor: avatarColor,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String deviceId,
                Value<String?> avatarColor = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => PlayersCompanion.insert(
                id: id,
                name: name,
                deviceId: deviceId,
                avatarColor: avatarColor,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlayersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (sessionsRefs) db.sessions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (sessionsRefs)
                    await $_getPrefetchedData<Player, $PlayersTable, Session>(
                      currentTable: table,
                      referencedTable: $$PlayersTableReferences
                          ._sessionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PlayersTableReferences(db, table, p0).sessionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.playerId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PlayersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayersTable,
      Player,
      $$PlayersTableFilterComposer,
      $$PlayersTableOrderingComposer,
      $$PlayersTableAnnotationComposer,
      $$PlayersTableCreateCompanionBuilder,
      $$PlayersTableUpdateCompanionBuilder,
      (Player, $$PlayersTableReferences),
      Player,
      PrefetchHooks Function({bool sessionsRefs})
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String playerId,
      required String kind,
      Value<String> mode,
      required double distanceMeters,
      Value<int?> throwTarget,
      Value<int?> finField,
      Value<int?> finBase,
      required String status,
      required DateTime startedAt,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> playerId,
      Value<String> kind,
      Value<String> mode,
      Value<double> distanceMeters,
      Value<int?> throwTarget,
      Value<int?> finField,
      Value<int?> finBase,
      Value<String> status,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PlayersTable _playerIdTable(_$AppDatabase db) => db.players
      .createAlias($_aliasNameGenerator(db.sessions.playerId, db.players.id));

  $$PlayersTableProcessedTableManager get playerId {
    final $_column = $_itemColumn<String>('player_id')!;

    final manager = $$PlayersTableTableManager(
      $_db,
      $_db.players,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SessionEventsTable, List<SessionEvent>>
  _sessionEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessionEvents,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.sessionEvents.sessionId),
  );

  $$SessionEventsTableProcessedTableManager get sessionEventsRefs {
    final manager = $$SessionEventsTableTableManager(
      $_db,
      $_db.sessionEvents,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $FinisseurStickEventsTable,
    List<FinisseurStickEvent>
  >
  _finisseurStickEventsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.finisseurStickEvents,
        aliasName: $_aliasNameGenerator(
          db.sessions.id,
          db.finisseurStickEvents.sessionId,
        ),
      );

  $$FinisseurStickEventsTableProcessedTableManager
  get finisseurStickEventsRefs {
    final manager = $$FinisseurStickEventsTableTableManager(
      $_db,
      $_db.finisseurStickEvents,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _finisseurStickEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get throwTarget => $composableBuilder(
    column: $table.throwTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finField => $composableBuilder(
    column: $table.finField,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finBase => $composableBuilder(
    column: $table.finBase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PlayersTableFilterComposer get playerId {
    final $$PlayersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playerId,
      referencedTable: $db.players,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayersTableFilterComposer(
            $db: $db,
            $table: $db.players,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sessionEventsRefs(
    Expression<bool> Function($$SessionEventsTableFilterComposer f) f,
  ) {
    final $$SessionEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionEventsTableFilterComposer(
            $db: $db,
            $table: $db.sessionEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> finisseurStickEventsRefs(
    Expression<bool> Function($$FinisseurStickEventsTableFilterComposer f) f,
  ) {
    final $$FinisseurStickEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.finisseurStickEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FinisseurStickEventsTableFilterComposer(
            $db: $db,
            $table: $db.finisseurStickEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get throwTarget => $composableBuilder(
    column: $table.throwTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finField => $composableBuilder(
    column: $table.finField,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finBase => $composableBuilder(
    column: $table.finBase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlayersTableOrderingComposer get playerId {
    final $$PlayersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playerId,
      referencedTable: $db.players,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayersTableOrderingComposer(
            $db: $db,
            $table: $db.players,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get throwTarget => $composableBuilder(
    column: $table.throwTarget,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finField =>
      $composableBuilder(column: $table.finField, builder: (column) => column);

  GeneratedColumn<int> get finBase =>
      $composableBuilder(column: $table.finBase, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  $$PlayersTableAnnotationComposer get playerId {
    final $$PlayersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playerId,
      referencedTable: $db.players,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayersTableAnnotationComposer(
            $db: $db,
            $table: $db.players,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sessionEventsRefs<T extends Object>(
    Expression<T> Function($$SessionEventsTableAnnotationComposer a) f,
  ) {
    final $$SessionEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> finisseurStickEventsRefs<T extends Object>(
    Expression<T> Function($$FinisseurStickEventsTableAnnotationComposer a) f,
  ) {
    final $$FinisseurStickEventsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.finisseurStickEvents,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$FinisseurStickEventsTableAnnotationComposer(
                $db: $db,
                $table: $db.finisseurStickEvents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({
            bool playerId,
            bool sessionEventsRefs,
            bool finisseurStickEventsRefs,
          })
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> playerId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<double> distanceMeters = const Value.absent(),
                Value<int?> throwTarget = const Value.absent(),
                Value<int?> finField = const Value.absent(),
                Value<int?> finBase = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                playerId: playerId,
                kind: kind,
                mode: mode,
                distanceMeters: distanceMeters,
                throwTarget: throwTarget,
                finField: finField,
                finBase: finBase,
                status: status,
                startedAt: startedAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String playerId,
                required String kind,
                Value<String> mode = const Value.absent(),
                required double distanceMeters,
                Value<int?> throwTarget = const Value.absent(),
                Value<int?> finField = const Value.absent(),
                Value<int?> finBase = const Value.absent(),
                required String status,
                required DateTime startedAt,
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                playerId: playerId,
                kind: kind,
                mode: mode,
                distanceMeters: distanceMeters,
                throwTarget: throwTarget,
                finField: finField,
                finBase: finBase,
                status: status,
                startedAt: startedAt,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                playerId = false,
                sessionEventsRefs = false,
                finisseurStickEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionEventsRefs) db.sessionEvents,
                    if (finisseurStickEventsRefs) db.finisseurStickEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (playerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.playerId,
                                    referencedTable: $$SessionsTableReferences
                                        ._playerIdTable(db),
                                    referencedColumn: $$SessionsTableReferences
                                        ._playerIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionEventsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          SessionEvent
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._sessionEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (finisseurStickEventsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          FinisseurStickEvent
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._finisseurStickEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).finisseurStickEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({
        bool playerId,
        bool sessionEventsRefs,
        bool finisseurStickEventsRefs,
      })
    >;
typedef $$SessionEventsTableCreateCompanionBuilder =
    SessionEventsCompanion Function({
      required String id,
      required String sessionId,
      required String kind,
      required DateTime createdAt,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });
typedef $$SessionEventsTableUpdateCompanionBuilder =
    SessionEventsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> kind,
      Value<DateTime> createdAt,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });

final class $$SessionEventsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionEventsTable, SessionEvent> {
  $$SessionEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.sessionEvents.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionEventsTable> {
  $$SessionEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => column,
  );

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionEventsTable,
          SessionEvent,
          $$SessionEventsTableFilterComposer,
          $$SessionEventsTableOrderingComposer,
          $$SessionEventsTableAnnotationComposer,
          $$SessionEventsTableCreateCompanionBuilder,
          $$SessionEventsTableUpdateCompanionBuilder,
          (SessionEvent, $$SessionEventsTableReferences),
          SessionEvent,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SessionEventsTableTableManager(_$AppDatabase db, $SessionEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionEventsCompanion(
                id: id,
                sessionId: sessionId,
                kind: kind,
                createdAt: createdAt,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String kind,
                required DateTime createdAt,
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                kind: kind,
                createdAt: createdAt,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$SessionEventsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$SessionEventsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SessionEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionEventsTable,
      SessionEvent,
      $$SessionEventsTableFilterComposer,
      $$SessionEventsTableOrderingComposer,
      $$SessionEventsTableAnnotationComposer,
      $$SessionEventsTableCreateCompanionBuilder,
      $$SessionEventsTableUpdateCompanionBuilder,
      (SessionEvent, $$SessionEventsTableReferences),
      SessionEvent,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$AppSettingsTableTableCreateCompanionBuilder =
    AppSettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableTableUpdateCompanionBuilder =
    AppSettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData,
          $$AppSettingsTableTableFilterComposer,
          $$AppSettingsTableTableOrderingComposer,
          $$AppSettingsTableTableAnnotationComposer,
          $$AppSettingsTableTableCreateCompanionBuilder,
          $$AppSettingsTableTableUpdateCompanionBuilder,
          (
            AppSettingsTableData,
            BaseReferences<
              _$AppDatabase,
              $AppSettingsTableTable,
              AppSettingsTableData
            >,
          ),
          AppSettingsTableData,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableTableManager(
    _$AppDatabase db,
    $AppSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsTableCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTableTable,
      AppSettingsTableData,
      $$AppSettingsTableTableFilterComposer,
      $$AppSettingsTableTableOrderingComposer,
      $$AppSettingsTableTableAnnotationComposer,
      $$AppSettingsTableTableCreateCompanionBuilder,
      $$AppSettingsTableTableUpdateCompanionBuilder,
      (
        AppSettingsTableData,
        BaseReferences<
          _$AppDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData
        >,
      ),
      AppSettingsTableData,
      PrefetchHooks Function()
    >;
typedef $$FinisseurStickEventsTableCreateCompanionBuilder =
    FinisseurStickEventsCompanion Function({
      required String id,
      required String sessionId,
      required int stickIndex,
      Value<int> fieldKubbsHit,
      Value<bool> eightMHit,
      Value<bool> heliThrow,
      Value<bool?> kingHit,
      Value<String?> kingPosition,
      Value<int> penaltyHits1,
      Value<int> penaltyHits2,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$FinisseurStickEventsTableUpdateCompanionBuilder =
    FinisseurStickEventsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<int> stickIndex,
      Value<int> fieldKubbsHit,
      Value<bool> eightMHit,
      Value<bool> heliThrow,
      Value<bool?> kingHit,
      Value<String?> kingPosition,
      Value<int> penaltyHits1,
      Value<int> penaltyHits2,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$FinisseurStickEventsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $FinisseurStickEventsTable,
          FinisseurStickEvent
        > {
  $$FinisseurStickEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.finisseurStickEvents.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FinisseurStickEventsTableFilterComposer
    extends Composer<_$AppDatabase, $FinisseurStickEventsTable> {
  $$FinisseurStickEventsTableFilterComposer({
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

  ColumnFilters<int> get stickIndex => $composableBuilder(
    column: $table.stickIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fieldKubbsHit => $composableBuilder(
    column: $table.fieldKubbsHit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get eightMHit => $composableBuilder(
    column: $table.eightMHit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get heliThrow => $composableBuilder(
    column: $table.heliThrow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get kingHit => $composableBuilder(
    column: $table.kingHit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kingPosition => $composableBuilder(
    column: $table.kingPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get penaltyHits1 => $composableBuilder(
    column: $table.penaltyHits1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get penaltyHits2 => $composableBuilder(
    column: $table.penaltyHits2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinisseurStickEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $FinisseurStickEventsTable> {
  $$FinisseurStickEventsTableOrderingComposer({
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

  ColumnOrderings<int> get stickIndex => $composableBuilder(
    column: $table.stickIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fieldKubbsHit => $composableBuilder(
    column: $table.fieldKubbsHit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get eightMHit => $composableBuilder(
    column: $table.eightMHit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get heliThrow => $composableBuilder(
    column: $table.heliThrow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get kingHit => $composableBuilder(
    column: $table.kingHit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kingPosition => $composableBuilder(
    column: $table.kingPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get penaltyHits1 => $composableBuilder(
    column: $table.penaltyHits1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get penaltyHits2 => $composableBuilder(
    column: $table.penaltyHits2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinisseurStickEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FinisseurStickEventsTable> {
  $$FinisseurStickEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get stickIndex => $composableBuilder(
    column: $table.stickIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fieldKubbsHit => $composableBuilder(
    column: $table.fieldKubbsHit,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get eightMHit =>
      $composableBuilder(column: $table.eightMHit, builder: (column) => column);

  GeneratedColumn<bool> get heliThrow =>
      $composableBuilder(column: $table.heliThrow, builder: (column) => column);

  GeneratedColumn<bool> get kingHit =>
      $composableBuilder(column: $table.kingHit, builder: (column) => column);

  GeneratedColumn<String> get kingPosition => $composableBuilder(
    column: $table.kingPosition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get penaltyHits1 => $composableBuilder(
    column: $table.penaltyHits1,
    builder: (column) => column,
  );

  GeneratedColumn<int> get penaltyHits2 => $composableBuilder(
    column: $table.penaltyHits2,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinisseurStickEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FinisseurStickEventsTable,
          FinisseurStickEvent,
          $$FinisseurStickEventsTableFilterComposer,
          $$FinisseurStickEventsTableOrderingComposer,
          $$FinisseurStickEventsTableAnnotationComposer,
          $$FinisseurStickEventsTableCreateCompanionBuilder,
          $$FinisseurStickEventsTableUpdateCompanionBuilder,
          (FinisseurStickEvent, $$FinisseurStickEventsTableReferences),
          FinisseurStickEvent,
          PrefetchHooks Function({bool sessionId})
        > {
  $$FinisseurStickEventsTableTableManager(
    _$AppDatabase db,
    $FinisseurStickEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FinisseurStickEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FinisseurStickEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FinisseurStickEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> stickIndex = const Value.absent(),
                Value<int> fieldKubbsHit = const Value.absent(),
                Value<bool> eightMHit = const Value.absent(),
                Value<bool> heliThrow = const Value.absent(),
                Value<bool?> kingHit = const Value.absent(),
                Value<String?> kingPosition = const Value.absent(),
                Value<int> penaltyHits1 = const Value.absent(),
                Value<int> penaltyHits2 = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FinisseurStickEventsCompanion(
                id: id,
                sessionId: sessionId,
                stickIndex: stickIndex,
                fieldKubbsHit: fieldKubbsHit,
                eightMHit: eightMHit,
                heliThrow: heliThrow,
                kingHit: kingHit,
                kingPosition: kingPosition,
                penaltyHits1: penaltyHits1,
                penaltyHits2: penaltyHits2,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required int stickIndex,
                Value<int> fieldKubbsHit = const Value.absent(),
                Value<bool> eightMHit = const Value.absent(),
                Value<bool> heliThrow = const Value.absent(),
                Value<bool?> kingHit = const Value.absent(),
                Value<String?> kingPosition = const Value.absent(),
                Value<int> penaltyHits1 = const Value.absent(),
                Value<int> penaltyHits2 = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FinisseurStickEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                stickIndex: stickIndex,
                fieldKubbsHit: fieldKubbsHit,
                eightMHit: eightMHit,
                heliThrow: heliThrow,
                kingHit: kingHit,
                kingPosition: kingPosition,
                penaltyHits1: penaltyHits1,
                penaltyHits2: penaltyHits2,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FinisseurStickEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$FinisseurStickEventsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$FinisseurStickEventsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FinisseurStickEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FinisseurStickEventsTable,
      FinisseurStickEvent,
      $$FinisseurStickEventsTableFilterComposer,
      $$FinisseurStickEventsTableOrderingComposer,
      $$FinisseurStickEventsTableAnnotationComposer,
      $$FinisseurStickEventsTableCreateCompanionBuilder,
      $$FinisseurStickEventsTableUpdateCompanionBuilder,
      (FinisseurStickEvent, $$FinisseurStickEventsTableReferences),
      FinisseurStickEvent,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$CachedAuthSessionTableCreateCompanionBuilder =
    CachedAuthSessionCompanion Function({
      Value<String> id,
      required String userId,
      required String kind,
      required String displayName,
      Value<String?> avatarColor,
      required DateTime expiresAt,
      required DateTime refreshAfter,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedAuthSessionTableUpdateCompanionBuilder =
    CachedAuthSessionCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> kind,
      Value<String> displayName,
      Value<String?> avatarColor,
      Value<DateTime> expiresAt,
      Value<DateTime> refreshAfter,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedAuthSessionTableFilterComposer
    extends Composer<_$AppDatabase, $CachedAuthSessionTable> {
  $$CachedAuthSessionTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshAfter => $composableBuilder(
    column: $table.refreshAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedAuthSessionTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedAuthSessionTable> {
  $$CachedAuthSessionTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshAfter => $composableBuilder(
    column: $table.refreshAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedAuthSessionTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedAuthSessionTable> {
  $$CachedAuthSessionTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshAfter => $composableBuilder(
    column: $table.refreshAfter,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedAuthSessionTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedAuthSessionTable,
          CachedAuthSessionData,
          $$CachedAuthSessionTableFilterComposer,
          $$CachedAuthSessionTableOrderingComposer,
          $$CachedAuthSessionTableAnnotationComposer,
          $$CachedAuthSessionTableCreateCompanionBuilder,
          $$CachedAuthSessionTableUpdateCompanionBuilder,
          (
            CachedAuthSessionData,
            BaseReferences<
              _$AppDatabase,
              $CachedAuthSessionTable,
              CachedAuthSessionData
            >,
          ),
          CachedAuthSessionData,
          PrefetchHooks Function()
        > {
  $$CachedAuthSessionTableTableManager(
    _$AppDatabase db,
    $CachedAuthSessionTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedAuthSessionTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedAuthSessionTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedAuthSessionTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarColor = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<DateTime> refreshAfter = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedAuthSessionCompanion(
                id: id,
                userId: userId,
                kind: kind,
                displayName: displayName,
                avatarColor: avatarColor,
                expiresAt: expiresAt,
                refreshAfter: refreshAfter,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String userId,
                required String kind,
                required String displayName,
                Value<String?> avatarColor = const Value.absent(),
                required DateTime expiresAt,
                required DateTime refreshAfter,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedAuthSessionCompanion.insert(
                id: id,
                userId: userId,
                kind: kind,
                displayName: displayName,
                avatarColor: avatarColor,
                expiresAt: expiresAt,
                refreshAfter: refreshAfter,
                createdAt: createdAt,
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

typedef $$CachedAuthSessionTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedAuthSessionTable,
      CachedAuthSessionData,
      $$CachedAuthSessionTableFilterComposer,
      $$CachedAuthSessionTableOrderingComposer,
      $$CachedAuthSessionTableAnnotationComposer,
      $$CachedAuthSessionTableCreateCompanionBuilder,
      $$CachedAuthSessionTableUpdateCompanionBuilder,
      (
        CachedAuthSessionData,
        BaseReferences<
          _$AppDatabase,
          $CachedAuthSessionTable,
          CachedAuthSessionData
        >,
      ),
      CachedAuthSessionData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PlayersTableTableManager get players =>
      $$PlayersTableTableManager(_db, _db.players);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SessionEventsTableTableManager get sessionEvents =>
      $$SessionEventsTableTableManager(_db, _db.sessionEvents);
  $$AppSettingsTableTableTableManager get appSettingsTable =>
      $$AppSettingsTableTableTableManager(_db, _db.appSettingsTable);
  $$FinisseurStickEventsTableTableManager get finisseurStickEvents =>
      $$FinisseurStickEventsTableTableManager(_db, _db.finisseurStickEvents);
  $$CachedAuthSessionTableTableManager get cachedAuthSession =>
      $$CachedAuthSessionTableTableManager(_db, _db.cachedAuthSession);
}
