// =============================================================================
// NOTITIA — Modèle de résumé riche (IA)
// =============================================================================

/// Une source web réelle (grounding Google Search)
class SummarySource {
  final String title;
  final String url;
  final String snippet;

  SummarySource({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'snippet': snippet,
  };

  factory SummarySource.fromJson(Map<String, dynamic> json) => SummarySource(
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    snippet: json['snippet'] as String? ?? '',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Visuels : chiffres clés, graphiques, étapes, citations
// ─────────────────────────────────────────────────────────────────────────────

/// Un chiffre clé mis en valeur
class KeyFigure {
  final String value;
  final String label;
  final String? icon; // nom Material Icon (ex: "trending_up")

  KeyFigure({required this.value, required this.label, this.icon});

  Map<String, dynamic> toJson() => {
    'value': value,
    'label': label,
    if (icon != null) 'icon': icon,
  };

  factory KeyFigure.fromJson(Map<String, dynamic> json) => KeyFigure(
    value: json['value'] as String? ?? '',
    label: json['label'] as String? ?? '',
    icon: json['icon'] as String?,
  );
}

/// Une entrée de graphique (bar chart / pie chart)
class ChartEntry {
  final String label;
  final double value;

  ChartEntry({required this.label, required this.value});

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  factory ChartEntry.fromJson(Map<String, dynamic> json) => ChartEntry(
    label: json['label'] as String? ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
  );
}

/// Une étape dans un processus / flowchart
class FlowStep {
  final String title;
  final String description;

  FlowStep({required this.title, required this.description});

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
  };

  factory FlowStep.fromJson(Map<String, dynamic> json) => FlowStep(
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );
}

/// Bloc visuel polymorphe attaché à une section
class SectionVisual {
  /// Type: "chart_bar", "chart_pie", "key_figures", "flow", "quote", "timeline"
  final String type;
  final String? chartTitle;
  final List<ChartEntry> chartData;
  final List<KeyFigure> keyFigures;
  final List<FlowStep> flowSteps;
  final String? quote;
  final String? quoteAuthor;

  SectionVisual({
    required this.type,
    this.chartTitle,
    this.chartData = const [],
    this.keyFigures = const [],
    this.flowSteps = const [],
    this.quote,
    this.quoteAuthor,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    if (chartTitle != null) 'chart_title': chartTitle,
    if (chartData.isNotEmpty) 'chart_data': chartData.map((e) => e.toJson()).toList(),
    if (keyFigures.isNotEmpty) 'key_figures': keyFigures.map((e) => e.toJson()).toList(),
    if (flowSteps.isNotEmpty) 'flow_steps': flowSteps.map((e) => e.toJson()).toList(),
    if (quote != null) 'quote': quote,
    if (quoteAuthor != null) 'quote_author': quoteAuthor,
  };

  factory SectionVisual.fromJson(Map<String, dynamic> json) {
    return SectionVisual(
      type: json['type'] as String? ?? 'none',
      chartTitle: json['chart_title'] as String?,
      chartData: (json['chart_data'] as List<dynamic>?)
              ?.map((e) => ChartEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      keyFigures: (json['key_figures'] as List<dynamic>?)
              ?.map((e) => KeyFigure.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      flowSteps: (json['flow_steps'] as List<dynamic>?)
              ?.map((e) => FlowStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      quote: json['quote'] as String?,
      quoteAuthor: json['quote_author'] as String?,
    );
  }
}

/// Une section du résumé avec contenu, visuels, image et sources
class SummarySection {
  final String heading;
  final String content;
  final String? imageUrl;
  final List<SummarySource> sources;
  final SectionVisual? visual;

  SummarySection({
    required this.heading,
    required this.content,
    this.imageUrl,
    this.sources = const [],
    this.visual,
  });

  Map<String, dynamic> toJson() => {
    'heading': heading,
    'content': content,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'sources': sources.map((s) => s.toJson()).toList(),
    if (visual != null) 'visual': visual!.toJson(),
  };

  factory SummarySection.fromJson(Map<String, dynamic> json) => SummarySection(
    heading: json['heading'] as String? ?? '',
    content: json['content'] as String? ?? '',
    imageUrl: json['imageUrl'] as String?,
    sources: (json['sources'] as List<dynamic>?)
            ?.map((s) => SummarySource.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [],
    visual: json['visual'] != null
        ? SectionVisual.fromJson(json['visual'] as Map<String, dynamic>)
        : null,
  );
}

/// Résumé riche complet d'une transcription
class RichSummary {
  final String transcriptionId;
  final String title;
  final String introduction;
  final List<KeyFigure> topFigures; // chiffres clés globaux en haut
  final List<SummarySection> sections;
  final DateTime generatedAt;

  RichSummary({
    required this.transcriptionId,
    required this.title,
    required this.introduction,
    this.topFigures = const [],
    required this.sections,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'transcriptionId': transcriptionId,
    'title': title,
    'introduction': introduction,
    'topFigures': topFigures.map((f) => f.toJson()).toList(),
    'sections': sections.map((s) => s.toJson()).toList(),
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory RichSummary.fromJson(Map<String, dynamic> json) => RichSummary(
    transcriptionId: json['transcriptionId'] as String,
    title: json['title'] as String? ?? '',
    introduction: json['introduction'] as String? ?? '',
    topFigures: (json['topFigures'] as List<dynamic>?)
            ?.map((f) => KeyFigure.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [],
    sections: (json['sections'] as List<dynamic>?)
            ?.map((s) => SummarySection.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [],
    generatedAt: DateTime.parse(json['generatedAt'] as String),
  );
}
