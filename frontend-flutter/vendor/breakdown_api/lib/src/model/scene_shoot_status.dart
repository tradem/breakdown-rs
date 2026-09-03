// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_shoot_status.g.dart';

/// The shoot status lifecycle of a `SceneShoot`.  `Planned` — the scene is planned (Dispo), no execution data yet. `Scheduled` — the scene is scheduled but not yet in progress. `InProgress` — execution has started (`start_dt` or `actual_order` set). `Shot` — the scene shoot is finished (terminal for this pair). `Skipped` — the scene was skipped on this shooting day.
class SceneShootStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'Planned')
  static const SceneShootStatus planned = _$planned;
  @BuiltValueEnumConst(wireName: r'Scheduled')
  static const SceneShootStatus scheduled = _$scheduled;
  @BuiltValueEnumConst(wireName: r'InProgress')
  static const SceneShootStatus inProgress = _$inProgress;
  @BuiltValueEnumConst(wireName: r'Shot')
  static const SceneShootStatus shot = _$shot;
  @BuiltValueEnumConst(wireName: r'Skipped')
  static const SceneShootStatus skipped = _$skipped;

  static Serializer<SceneShootStatus> get serializer =>
      _$sceneShootStatusSerializer;

  const SceneShootStatus._(String name) : super(name);

  static BuiltSet<SceneShootStatus> get values => _$values;
  static SceneShootStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class SceneShootStatusMixin = Object with _$SceneShootStatusMixin;
