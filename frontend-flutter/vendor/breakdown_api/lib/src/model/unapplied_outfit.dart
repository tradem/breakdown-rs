// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/unapplied_outfit_reason.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unapplied_outfit.g.dart';

/// Why an outfit row did not become an `Outfit`. Shown to the reviewer as *missing with a reason* instead of as a successful apply.
///
/// Properties:
/// * [characterName]
/// * [detail] - Short diagnostic (e.g. the rejection the aggregate returned). The UI branches on [`Self::reason`], never on this text.
/// * [draftRef]
/// * [name]
/// * [ordinal]
/// * [reason]
@BuiltValue()
abstract class UnappliedOutfit
    implements Built<UnappliedOutfit, UnappliedOutfitBuilder> {
  @BuiltValueField(wireName: r'character_name')
  String get characterName;

  /// Short diagnostic (e.g. the rejection the aggregate returned). The UI branches on [`Self::reason`], never on this text.
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'ordinal')
  int get ordinal;

  @BuiltValueField(wireName: r'reason')
  UnappliedOutfitReason get reason;
  // enum reasonEnum {  character_not_planned,  character_unavailable,  piece_rejected,  create_rejected,  notes_rejected,  binding_rejected,  beat_rejected,  };

  UnappliedOutfit._();

  factory UnappliedOutfit([void updates(UnappliedOutfitBuilder b)]) =
      _$UnappliedOutfit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnappliedOutfitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnappliedOutfit> get serializer =>
      _$UnappliedOutfitSerializer();
}

class _$UnappliedOutfitSerializer
    implements PrimitiveSerializer<UnappliedOutfit> {
  @override
  final Iterable<Type> types = const [UnappliedOutfit, _$UnappliedOutfit];

  @override
  final String wireName = r'UnappliedOutfit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnappliedOutfit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_name';
    yield serializers.serialize(
      object.characterName,
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
    yield r'name';
    yield serializers.serialize(
      object.name,
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
      specifiedType: const FullType(UnappliedOutfitReason),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UnappliedOutfit object, {
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
    required UnappliedOutfitBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
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
            specifiedType: const FullType(UnappliedOutfitReason),
          ) as UnappliedOutfitReason;
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
  UnappliedOutfit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnappliedOutfitBuilder();
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
