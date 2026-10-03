// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/unapplied_costume_reason.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unapplied_costume.g.dart';

/// Why a costume row did not become a `Costume`. Shown to the reviewer as *missing with a reason* instead of as a successful apply.
///
/// Properties:
/// * [characterName]
/// * [description]
/// * [detail] - Short diagnostic (e.g. the rejection the aggregate returned). The UI branches on [`Self::reason`], never on this text.
/// * [draftRef]
/// * [ordinal]
/// * [reason]
@BuiltValue()
abstract class UnappliedCostume
    implements Built<UnappliedCostume, UnappliedCostumeBuilder> {
  @BuiltValueField(wireName: r'character_name')
  String get characterName;

  @BuiltValueField(wireName: r'description')
  String get description;

  /// Short diagnostic (e.g. the rejection the aggregate returned). The UI branches on [`Self::reason`], never on this text.
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  @BuiltValueField(wireName: r'ordinal')
  int get ordinal;

  @BuiltValueField(wireName: r'reason')
  UnappliedCostumeReason get reason;
  // enum reasonEnum {  character_not_planned,  character_unavailable,  create_rejected,  notes_rejected,  binding_rejected,  beat_rejected,  };

  UnappliedCostume._();

  factory UnappliedCostume([void updates(UnappliedCostumeBuilder b)]) =
      _$UnappliedCostume;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnappliedCostumeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnappliedCostume> get serializer =>
      _$UnappliedCostumeSerializer();
}

class _$UnappliedCostumeSerializer
    implements PrimitiveSerializer<UnappliedCostume> {
  @override
  final Iterable<Type> types = const [UnappliedCostume, _$UnappliedCostume];

  @override
  final String wireName = r'UnappliedCostume';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnappliedCostume object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_name';
    yield serializers.serialize(
      object.characterName,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'draft_ref';
    yield serializers.serialize(
      object.draftRef,
      specifiedType: const FullType(String),
    );
    yield r'ordinal';
    yield serializers.serialize(
      object.ordinal,
      specifiedType: const FullType(int),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(UnappliedCostumeReason),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UnappliedCostume object, {
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
    required UnappliedCostumeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterName = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.detail = valueDes;
          break;
        case r'draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.draftRef = valueDes;
          break;
        case r'ordinal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ordinal = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UnappliedCostumeReason),
          ) as UnappliedCostumeReason;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UnappliedCostume deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnappliedCostumeBuilder();
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
