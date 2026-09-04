// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_preview_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportPreviewResponse extends AiImportPreviewResponse {
  @override
  final DocumentKind documentKind;
  @override
  final String jobId;
  @override
  final AiPreviewPayload preview;
  @override
  final JobStatus status;

  factory _$AiImportPreviewResponse(
          [void Function(AiImportPreviewResponseBuilder)? updates]) =>
      (AiImportPreviewResponseBuilder()..update(updates))._build();

  _$AiImportPreviewResponse._(
      {required this.documentKind,
      required this.jobId,
      required this.preview,
      required this.status})
      : super._();
  @override
  AiImportPreviewResponse rebuild(
          void Function(AiImportPreviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportPreviewResponseBuilder toBuilder() =>
      AiImportPreviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportPreviewResponse &&
        documentKind == other.documentKind &&
        jobId == other.jobId &&
        preview == other.preview &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, documentKind.hashCode);
    _$hash = $jc(_$hash, jobId.hashCode);
    _$hash = $jc(_$hash, preview.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportPreviewResponse')
          ..add('documentKind', documentKind)
          ..add('jobId', jobId)
          ..add('preview', preview)
          ..add('status', status))
        .toString();
  }
}

class AiImportPreviewResponseBuilder
    implements
        Builder<AiImportPreviewResponse, AiImportPreviewResponseBuilder> {
  _$AiImportPreviewResponse? _$v;

  DocumentKind? _documentKind;
  DocumentKind? get documentKind => _$this._documentKind;
  set documentKind(DocumentKind? documentKind) =>
      _$this._documentKind = documentKind;

  String? _jobId;
  String? get jobId => _$this._jobId;
  set jobId(String? jobId) => _$this._jobId = jobId;

  AiPreviewPayloadBuilder? _preview;
  AiPreviewPayloadBuilder get preview =>
      _$this._preview ??= AiPreviewPayloadBuilder();
  set preview(AiPreviewPayloadBuilder? preview) => _$this._preview = preview;

  JobStatus? _status;
  JobStatus? get status => _$this._status;
  set status(JobStatus? status) => _$this._status = status;

  AiImportPreviewResponseBuilder() {
    AiImportPreviewResponse._defaults(this);
  }

  AiImportPreviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _documentKind = $v.documentKind;
      _jobId = $v.jobId;
      _preview = $v.preview.toBuilder();
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportPreviewResponse other) {
    _$v = other as _$AiImportPreviewResponse;
  }

  @override
  void update(void Function(AiImportPreviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportPreviewResponse build() => _build();

  _$AiImportPreviewResponse _build() {
    _$AiImportPreviewResponse _$result;
    try {
      _$result = _$v ??
          _$AiImportPreviewResponse._(
            documentKind: BuiltValueNullFieldError.checkNotNull(
                documentKind, r'AiImportPreviewResponse', 'documentKind'),
            jobId: BuiltValueNullFieldError.checkNotNull(
                jobId, r'AiImportPreviewResponse', 'jobId'),
            preview: preview.build(),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'AiImportPreviewResponse', 'status'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'preview';
        preview.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiImportPreviewResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
