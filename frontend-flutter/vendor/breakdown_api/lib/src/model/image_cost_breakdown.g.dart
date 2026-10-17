// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_cost_breakdown.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ImageCostBreakdown extends ImageCostBreakdown {
  @override
  final int? imageNanoPerUnit;
  @override
  final int? imageOutputRateNanoPerMillion;
  @override
  final int imageOutputTokens;
  @override
  final int images;
  @override
  final int totalNano;

  factory _$ImageCostBreakdown(
          [void Function(ImageCostBreakdownBuilder)? updates]) =>
      (ImageCostBreakdownBuilder()..update(updates))._build();

  _$ImageCostBreakdown._(
      {this.imageNanoPerUnit,
      this.imageOutputRateNanoPerMillion,
      required this.imageOutputTokens,
      required this.images,
      required this.totalNano})
      : super._();
  @override
  ImageCostBreakdown rebuild(
          void Function(ImageCostBreakdownBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImageCostBreakdownBuilder toBuilder() =>
      ImageCostBreakdownBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImageCostBreakdown &&
        imageNanoPerUnit == other.imageNanoPerUnit &&
        imageOutputRateNanoPerMillion == other.imageOutputRateNanoPerMillion &&
        imageOutputTokens == other.imageOutputTokens &&
        images == other.images &&
        totalNano == other.totalNano;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, imageNanoPerUnit.hashCode);
    _$hash = $jc(_$hash, imageOutputRateNanoPerMillion.hashCode);
    _$hash = $jc(_$hash, imageOutputTokens.hashCode);
    _$hash = $jc(_$hash, images.hashCode);
    _$hash = $jc(_$hash, totalNano.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ImageCostBreakdown')
          ..add('imageNanoPerUnit', imageNanoPerUnit)
          ..add('imageOutputRateNanoPerMillion', imageOutputRateNanoPerMillion)
          ..add('imageOutputTokens', imageOutputTokens)
          ..add('images', images)
          ..add('totalNano', totalNano))
        .toString();
  }
}

class ImageCostBreakdownBuilder
    implements Builder<ImageCostBreakdown, ImageCostBreakdownBuilder> {
  _$ImageCostBreakdown? _$v;

  int? _imageNanoPerUnit;
  int? get imageNanoPerUnit => _$this._imageNanoPerUnit;
  set imageNanoPerUnit(int? imageNanoPerUnit) =>
      _$this._imageNanoPerUnit = imageNanoPerUnit;

  int? _imageOutputRateNanoPerMillion;
  int? get imageOutputRateNanoPerMillion =>
      _$this._imageOutputRateNanoPerMillion;
  set imageOutputRateNanoPerMillion(int? imageOutputRateNanoPerMillion) =>
      _$this._imageOutputRateNanoPerMillion = imageOutputRateNanoPerMillion;

  int? _imageOutputTokens;
  int? get imageOutputTokens => _$this._imageOutputTokens;
  set imageOutputTokens(int? imageOutputTokens) =>
      _$this._imageOutputTokens = imageOutputTokens;

  int? _images;
  int? get images => _$this._images;
  set images(int? images) => _$this._images = images;

  int? _totalNano;
  int? get totalNano => _$this._totalNano;
  set totalNano(int? totalNano) => _$this._totalNano = totalNano;

  ImageCostBreakdownBuilder() {
    ImageCostBreakdown._defaults(this);
  }

  ImageCostBreakdownBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _imageNanoPerUnit = $v.imageNanoPerUnit;
      _imageOutputRateNanoPerMillion = $v.imageOutputRateNanoPerMillion;
      _imageOutputTokens = $v.imageOutputTokens;
      _images = $v.images;
      _totalNano = $v.totalNano;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImageCostBreakdown other) {
    _$v = other as _$ImageCostBreakdown;
  }

  @override
  void update(void Function(ImageCostBreakdownBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImageCostBreakdown build() => _build();

  _$ImageCostBreakdown _build() {
    final _$result = _$v ??
        _$ImageCostBreakdown._(
          imageNanoPerUnit: imageNanoPerUnit,
          imageOutputRateNanoPerMillion: imageOutputRateNanoPerMillion,
          imageOutputTokens: BuiltValueNullFieldError.checkNotNull(
              imageOutputTokens, r'ImageCostBreakdown', 'imageOutputTokens'),
          images: BuiltValueNullFieldError.checkNotNull(
              images, r'ImageCostBreakdown', 'images'),
          totalNano: BuiltValueNullFieldError.checkNotNull(
              totalNano, r'ImageCostBreakdown', 'totalNano'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
