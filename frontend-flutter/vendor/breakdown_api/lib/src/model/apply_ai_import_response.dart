// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/unapplied_outfit.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_ai_import_response.g.dart';

/// ApplyAiImportResponse
///
/// Properties:
/// * [appliedCount]
/// * [createdCharacters] - Figures the script apply created. A figure named by several draft rows is created once, so this is not `applied_count`-related. `0` for a schedule apply, which has no figures.
/// * [createdDays]
/// * [createdEpisodes] - Episodes the script apply created for draft episode groups the reviewer mapped to a NEW episode (issue #581). `0` for a schedule apply.
/// * [createdOutfits] - Outfits the script apply created — one look per accepted outfit row, bound to its figure and referencing the pieces above.
/// * [createdPieces] - Fundus pieces the script apply created — the garments of the extracted outfits.
/// * [plannedSceneShoots]
/// * [skippedDayGroups] - Day groups the reviewer rejected — their rows applied unscheduled (issue #706). Reported so the reviewer sees the deliberate omission, never a silent one.
/// * [unappliedOutfits] - Outfit rows that were **not** fully applied, each with the reason. An apply that created a piece but could not assemble the look reports the row here while `created_pieces` still counts the pieces — a partially applied row must never look like a fully applied one.
@BuiltValue()
abstract class ApplyAiImportResponse
    implements Built<ApplyAiImportResponse, ApplyAiImportResponseBuilder> {
  @BuiltValueField(wireName: r'applied_count')
  int get appliedCount;

  /// Figures the script apply created. A figure named by several draft rows is created once, so this is not `applied_count`-related. `0` for a schedule apply, which has no figures.
  @BuiltValueField(wireName: r'created_characters')
  int get createdCharacters;

  @BuiltValueField(wireName: r'created_days')
  int get createdDays;

  /// Episodes the script apply created for draft episode groups the reviewer mapped to a NEW episode (issue #581). `0` for a schedule apply.
  @BuiltValueField(wireName: r'created_episodes')
  int get createdEpisodes;

  /// Outfits the script apply created — one look per accepted outfit row, bound to its figure and referencing the pieces above.
  @BuiltValueField(wireName: r'created_outfits')
  int get createdOutfits;

  /// Fundus pieces the script apply created — the garments of the extracted outfits.
  @BuiltValueField(wireName: r'created_pieces')
  int get createdPieces;

  @BuiltValueField(wireName: r'planned_scene_shoots')
  int get plannedSceneShoots;

  /// Day groups the reviewer rejected — their rows applied unscheduled (issue #706). Reported so the reviewer sees the deliberate omission, never a silent one.
  @BuiltValueField(wireName: r'skipped_day_groups')
  BuiltList<String>? get skippedDayGroups;

  /// Outfit rows that were **not** fully applied, each with the reason. An apply that created a piece but could not assemble the look reports the row here while `created_pieces` still counts the pieces — a partially applied row must never look like a fully applied one.
  @BuiltValueField(wireName: r'unapplied_outfits')
  BuiltList<UnappliedOutfit> get unappliedOutfits;

  ApplyAiImportResponse._();

  factory ApplyAiImportResponse(
      [void updates(ApplyAiImportResponseBuilder b)]) = _$ApplyAiImportResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyAiImportResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyAiImportResponse> get serializer =>
      _$ApplyAiImportResponseSerializer();
}

class _$ApplyAiImportResponseSerializer
    implements PrimitiveSerializer<ApplyAiImportResponse> {
  @override
  final Iterable<Type> types = const [
    ApplyAiImportResponse,
    _$ApplyAiImportResponse
  ];

  @override
  final String wireName = r'ApplyAiImportResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyAiImportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied_count';
    yield serializers.serialize(
      object.appliedCount,
      specifiedType: const FullType(int),
    );
    yield r'created_characters';
    yield serializers.serialize(
      object.createdCharacters,
      specifiedType: const FullType(int),
    );
    yield r'created_days';
    yield serializers.serialize(
      object.createdDays,
      specifiedType: const FullType(int),
    );
    yield r'created_episodes';
    yield serializers.serialize(
      object.createdEpisodes,
      specifiedType: const FullType(int),
    );
    yield r'created_outfits';
    yield serializers.serialize(
      object.createdOutfits,
      specifiedType: const FullType(int),
    );
    yield r'created_pieces';
    yield serializers.serialize(
      object.createdPieces,
      specifiedType: const FullType(int),
    );
    yield r'planned_scene_shoots';
    yield serializers.serialize(
      object.plannedSceneShoots,
      specifiedType: const FullType(int),
    );
    if (object.skippedDayGroups != null) {
      yield r'skipped_day_groups';
      yield serializers.serialize(
        object.skippedDayGroups,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'unapplied_outfits';
    yield serializers.serialize(
      object.unappliedOutfits,
      specifiedType: const FullType(BuiltList, [FullType(UnappliedOutfit)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyAiImportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ApplyAiImportResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.appliedCount = valueDes;
          break;
        case r'created_characters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdCharacters = valueDes;
          break;
        case r'created_days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdDays = valueDes;
          break;
        case r'created_episodes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdEpisodes = valueDes;
          break;
        case r'created_outfits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdOutfits = valueDes;
          break;
        case r'created_pieces':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdPieces = valueDes;
          break;
        case r'planned_scene_shoots':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.plannedSceneShoots = valueDes;
          break;
        case r'skipped_day_groups':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.skippedDayGroups.replace(valueDes);
          break;
        case r'unapplied_outfits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(UnappliedOutfit)]),
          ) as BuiltList<UnappliedOutfit>;
          result.unappliedOutfits.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyAiImportResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyAiImportResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
