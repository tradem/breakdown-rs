// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_episode.g.dart';

/// One episode of the source script, as the deterministic marker scan (and, as a fallback, the LLM) read it out of the document. Production scripts mark episodes as `Ep.: 3 (Titel)` — on the first page and repeated in the page headers (issue #581). Metadata only: it groups preview rows for the reviewer and names the episode an apply may create; it never resolves an aggregate id (that is the reviewer's per-group decision).
///
/// Properties:
/// * [number] - The number after `Ep.:`, when the marker carried one.
/// * [title] - The title in the trailing parentheses, when the marker carried one.
@BuiltValue()
abstract class DraftEpisode
    implements Built<DraftEpisode, DraftEpisodeBuilder> {
  /// The number after `Ep.:`, when the marker carried one.
  @BuiltValueField(wireName: r'number')
  int? get number;

  /// The title in the trailing parentheses, when the marker carried one.
  @BuiltValueField(wireName: r'title')
  String? get title;

  DraftEpisode._();

  factory DraftEpisode([void updates(DraftEpisodeBuilder b)]) = _$DraftEpisode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftEpisodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftEpisode> get serializer => _$DraftEpisodeSerializer();
}

class _$DraftEpisodeSerializer implements PrimitiveSerializer<DraftEpisode> {
  @override
  final Iterable<Type> types = const [DraftEpisode, _$DraftEpisode];

  @override
  final String wireName = r'DraftEpisode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftEpisode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.number != null) {
      yield r'number';
      yield serializers.serialize(
        object.number,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftEpisode object, {
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
    required DraftEpisodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.number = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.title = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftEpisode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftEpisodeBuilder();
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
