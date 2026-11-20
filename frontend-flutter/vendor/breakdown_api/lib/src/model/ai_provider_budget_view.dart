// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_provider_budget_view.g.dart';

/// The account's remaining budget, where the provider reports one (issue #942 W4).  `remaining: null` is meaningful and must not be collapsed into the absent `budget` object: it means the provider answered and reports **no limit configured**, which is the opposite of an exhausted account.
///
/// Properties:
/// * [remaining]
@BuiltValue()
abstract class AiProviderBudgetView
    implements Built<AiProviderBudgetView, AiProviderBudgetViewBuilder> {
  @BuiltValueField(wireName: r'remaining')
  double? get remaining;

  AiProviderBudgetView._();

  factory AiProviderBudgetView([void updates(AiProviderBudgetViewBuilder b)]) =
      _$AiProviderBudgetView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiProviderBudgetViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiProviderBudgetView> get serializer =>
      _$AiProviderBudgetViewSerializer();
}

class _$AiProviderBudgetViewSerializer
    implements PrimitiveSerializer<AiProviderBudgetView> {
  @override
  final Iterable<Type> types = const [
    AiProviderBudgetView,
    _$AiProviderBudgetView
  ];

  @override
  final String wireName = r'AiProviderBudgetView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiProviderBudgetView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.remaining != null) {
      yield r'remaining';
      yield serializers.serialize(
        object.remaining,
        specifiedType: const FullType.nullable(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AiProviderBudgetView object, {
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
    required AiProviderBudgetViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'remaining':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.remaining = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiProviderBudgetView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiProviderBudgetViewBuilder();
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
