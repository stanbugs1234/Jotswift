import 'dart:ui';

/// Who can use a skin.
enum SkinTier {
  /// Bundled with the app and available to everyone.
  free,

  /// Sold individually or in a bundle.
  paid,

  /// Included with a Motley Pro subscription.
  pro,
}

/// The ruling printed on a page.
enum PaperPattern { blank, lined, grid, dot }

/// Thrown when a skin manifest is missing a field or has a bad value.
class SkinManifestException implements Exception {
  SkinManifestException(this.skinId, this.message);

  final String skinId;
  final String message;

  @override
  String toString() => 'Invalid skin manifest "$skinId": $message';
}

/// The colors a skin uses for the app chrome.
class SkinColors {
  const SkinColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.outline,
    required this.error,
  });

  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color outline;
  final Color error;
}

/// How pages look under this skin.
class SkinPaper {
  const SkinPaper({
    required this.color,
    required this.lineColor,
    required this.pattern,
    required this.spacing,
    this.marginColor,
    this.texture,
  });

  final Color color;
  final Color lineColor;
  final Color? marginColor;
  final PaperPattern pattern;

  /// Distance between lines, grid cells or dots, in page units.
  final double spacing;

  /// Optional texture image, relative to the skin's folder.
  final String? texture;
}

/// Font family names. Any Google Fonts family name is allowed.
class SkinTypography {
  const SkinTypography({
    required this.heading,
    required this.body,
    required this.accent,
  });

  final String heading;
  final String body;

  /// A decorative font, typically handwriting-style, for planner headers.
  final String accent;
}

/// A parsed skin manifest (see docs/skins.md for the format).
class SkinManifest {
  const SkinManifest({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.tier,
    required this.brightness,
    required this.colors,
    required this.paper,
    required this.inkColors,
    required this.typography,
    required this.cornerRadius,
    this.productId,
    this.stickers = const [],
  });

  factory SkinManifest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || !_idPattern.hasMatch(id)) {
      throw SkinManifestException(
        '$id',
        '"id" must be lowercase letters, digits and underscores',
      );
    }
    final r = _Reader(id, json);

    final schemaVersion = r.integer('schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw SkinManifestException(
        id,
        'unsupported schemaVersion $schemaVersion '
        '(this app reads $currentSchemaVersion)',
      );
    }

    final tier = r.enumValue('tier', SkinTier.values);
    final productId = r.optionalString('productId');
    if (tier == SkinTier.paid && productId == null) {
      throw SkinManifestException(id, 'paid skins need a "productId"');
    }

    final colors = r.child('colors');
    final paper = r.child('paper');
    final typography = r.child('typography');

    final inkColors = r.list('inkColors').map((v) => r.color('inkColors', v));
    if (inkColors.isEmpty) {
      throw SkinManifestException(id, '"inkColors" must not be empty');
    }

    final spacing = paper.number('spacing');
    if (spacing < 8 || spacing > 200) {
      throw SkinManifestException(id, '"paper.spacing" must be 8–200');
    }

    return SkinManifest(
      id: id,
      version: r.integer('version'),
      name: r.string('name'),
      description: r.string('description'),
      tier: tier,
      productId: productId,
      brightness: r.enumValue('brightness', Brightness.values),
      colors: SkinColors(
        primary: colors.colorField('primary'),
        onPrimary: colors.colorField('onPrimary'),
        secondary: colors.colorField('secondary'),
        onSecondary: colors.colorField('onSecondary'),
        background: colors.colorField('background'),
        surface: colors.colorField('surface'),
        onSurface: colors.colorField('onSurface'),
        outline: colors.colorField('outline'),
        error: colors.colorField('error'),
      ),
      paper: SkinPaper(
        color: paper.colorField('color'),
        lineColor: paper.colorField('lineColor'),
        marginColor: paper.optionalColorField('marginColor'),
        pattern: paper.enumValue('pattern', PaperPattern.values),
        spacing: spacing,
        texture: paper.optionalString('texture'),
      ),
      inkColors: inkColors.toList(),
      typography: SkinTypography(
        heading: typography.string('heading'),
        body: typography.string('body'),
        accent: typography.string('accent'),
      ),
      cornerRadius: r.number('cornerRadius'),
      stickers: r.optionalList('stickers').cast<String>(),
    );
  }

  static const currentSchemaVersion = 1;
  static final _idPattern = RegExp(r'^[a-z0-9_]+$');

  final String id;

  /// Bumped whenever the skin's files change, so caches can refresh.
  final int version;
  final String name;
  final String description;
  final SkinTier tier;

  /// The store product that unlocks this skin (paid skins only).
  final String? productId;
  final Brightness brightness;
  final SkinColors colors;
  final SkinPaper paper;

  /// The pen palette offered while this skin is active.
  final List<Color> inkColors;
  final SkinTypography typography;
  final double cornerRadius;

  /// Sticker image paths, relative to the skin's folder.
  final List<String> stickers;

  bool get isFree => tier == SkinTier.free;
}

/// Parses "#RRGGBB" or "#AARRGGBB". Returns null if [value] is malformed.
Color? parseHexColor(String value) {
  final match = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(value);
  if (match == null) return null;
  final hex = match.group(1)!;
  final argb = int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return Color(argb);
}

/// Reads typed fields from one JSON object, with errors that name the field.
class _Reader {
  _Reader(this.skinId, this.json, [this.path = '']);

  final String skinId;
  final Map<String, dynamic> json;
  final String path;

  String _name(String key) => '$path$key';

  Never _fail(String key, String expected) => throw SkinManifestException(
    skinId,
    '"${_name(key)}" must be $expected (got ${json[key]})',
  );

  _Reader child(String key) {
    final value = json[key];
    if (value is! Map<String, dynamic>) _fail(key, 'an object');
    return _Reader(skinId, value, '${_name(key)}.');
  }

  String string(String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) _fail(key, 'a string');
    return value;
  }

  String? optionalString(String key) => json[key] == null ? null : string(key);

  int integer(String key) {
    final value = json[key];
    if (value is! int) _fail(key, 'an integer');
    return value;
  }

  double number(String key) {
    final value = json[key];
    if (value is! num) _fail(key, 'a number');
    return value.toDouble();
  }

  List<dynamic> list(String key) {
    final value = json[key];
    if (value is! List) _fail(key, 'a list');
    return value;
  }

  List<dynamic> optionalList(String key) =>
      json[key] == null ? const [] : list(key);

  T enumValue<T extends Enum>(String key, List<T> values) {
    final value = json[key];
    for (final v in values) {
      if (v.name == value) return v;
    }
    _fail(key, 'one of ${values.map((v) => v.name).join(', ')}');
  }

  Color color(String key, Object? value) {
    final parsed = value is String ? parseHexColor(value) : null;
    if (parsed == null) {
      throw SkinManifestException(
        skinId,
        '"${_name(key)}" must contain "#RRGGBB" colors (got $value)',
      );
    }
    return parsed;
  }

  Color colorField(String key) => color(key, json[key]);

  Color? optionalColorField(String key) =>
      json[key] == null ? null : colorField(key);
}
