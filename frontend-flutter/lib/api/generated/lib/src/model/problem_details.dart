// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'problem_details.g.dart';

/// An RFC 9457 problem document (ADR-031 D1).  Every error response (status ≥ 400) produced by the API is an instance of this document: `type` (derived from `code`), constant English `title`, `status`, stable `code`, localized `detail` (English until Tranche 3), and the `trace_id` extension for otel correlation.
///
/// Properties:
/// * [code] - Stable machine identity `{context}.{reason}` (the client contract).
/// * [detail] - Human-readable explanation; localized server-side (Tranche 3).
/// * [extensions] - Declared S0/S1 extension fields, if any (ADR-031 D4).
/// * [status] - Canonical HTTP status of this problem.
/// * [title] - Constant English title (never localized; cacheable, spec-stable).
/// * [traceId] - W3C trace id of the request's otel span (support correlation).
/// * [type] - Dereferencable documentation anchor, derived from the `code`.
@BuiltValue()
abstract class ProblemDetails
    implements Built<ProblemDetails, ProblemDetailsBuilder> {
  /// Stable machine identity `{context}.{reason}` (the client contract).
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Human-readable explanation; localized server-side (Tranche 3).
  @BuiltValueField(wireName: r'detail')
  String get detail;

  /// Declared S0/S1 extension fields, if any (ADR-031 D4).
  @BuiltValueField(wireName: r'extensions')
  BuiltMap<String, JsonObject?>? get extensions;

  /// Canonical HTTP status of this problem.
  @BuiltValueField(wireName: r'status')
  int get status;

  /// Constant English title (never localized; cacheable, spec-stable).
  @BuiltValueField(wireName: r'title')
  String get title;

  /// W3C trace id of the request's otel span (support correlation).
  @BuiltValueField(wireName: r'trace_id')
  String get traceId;

  /// Dereferencable documentation anchor, derived from the `code`.
  @BuiltValueField(wireName: r'type')
  String get type;

  ProblemDetails._();

  factory ProblemDetails([void updates(ProblemDetailsBuilder b)]) =
      _$ProblemDetails;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ProblemDetailsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ProblemDetails> get serializer =>
      _$ProblemDetailsSerializer();
}

class _$ProblemDetailsSerializer
    implements PrimitiveSerializer<ProblemDetails> {
  @override
  final Iterable<Type> types = const [ProblemDetails, _$ProblemDetails];

  @override
  final String wireName = r'ProblemDetails';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ProblemDetails object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'detail';
    yield serializers.serialize(
      object.detail,
      specifiedType: const FullType(String),
    );
    if (object.extensions != null) {
      yield r'extensions';
      yield serializers.serialize(
        object.extensions,
        specifiedType: const FullType.nullable(
            BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(int),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'trace_id';
    yield serializers.serialize(
      object.traceId,
      specifiedType: const FullType(String),
    );
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ProblemDetails object, {
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
    required ProblemDetailsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.detail = valueDes;
          break;
        case r'extensions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>?;
          if (valueDes == null) continue;
          result.extensions.replace(valueDes);
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.status = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'trace_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.traceId = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ProblemDetails deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ProblemDetailsBuilder();
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
