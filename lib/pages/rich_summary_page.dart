// =============================================================================
// NOTITIA — Page de résumé riche (Charts + Schemas + Images + Sources)
// =============================================================================
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/rich_summary.dart';
import '../models/transcription.dart';
import '../services/gemini_service.dart';
import '../services/summary_storage_service.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Couleurs néon pour les graphiques
// ─────────────────────────────────────────────────────────────────────────────
const _chartColors = [
  Color(0xFFFF0178), // neonPink
  Color(0xFF00E5FF), // neonCyan
  Color(0xFFFF3366), // red
  Color(0xFF7C4DFF), // purple
  Color(0xFF00E676), // green
  Color(0xFFFFD740), // amber
  Color(0xFFFF6E40), // deepOrange
  Color(0xFF448AFF), // blue
];

// ─────────────────────────────────────────────────────────────────────────────
// Mapping icon name → IconData
// ─────────────────────────────────────────────────────────────────────────────
IconData _iconFromName(String? name) {
  const map = <String, IconData>{
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'schedule': Icons.schedule,
    'people': Icons.people,
    'euro': Icons.euro,
    'star': Icons.star,
    'speed': Icons.speed,
    'memory': Icons.memory,
    'school': Icons.school,
    'work': Icons.work,
    'check_circle': Icons.check_circle,
    'warning': Icons.warning,
    'lightbulb': Icons.lightbulb,
    'rocket_launch': Icons.rocket_launch,
    'analytics': Icons.analytics,
  };
  return map[name] ?? Icons.insights;
}

class RichSummaryPage extends StatefulWidget {
  final Transcription transcription;

  const RichSummaryPage({super.key, required this.transcription});

  @override
  State<RichSummaryPage> createState() => _RichSummaryPageState();
}

class _RichSummaryPageState extends State<RichSummaryPage>
    with SingleTickerProviderStateMixin {
  RichSummary? _summary;
  bool _loading = true;
  String _statusText = 'Analyse de la transcription…';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadOrGenerate();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadOrGenerate() async {
    final cached = await SummaryStorageService.load(widget.transcription.id);
    if (cached != null) {
      setState(() {
        _summary = cached;
        _loading = false;
      });
      return;
    }
    await _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _statusText = 'Analyse du contenu…';
    });
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _statusText = 'Rédaction du résumé & graphiques…');

    final summary = await GeminiService.instance.generateRichSummary(
      transcriptionId: widget.transcription.id,
      transcriptionContent: widget.transcription.content,
      transcriptionTitle: widget.transcription.title,
    );
    await SummaryStorageService.save(summary);

    if (mounted) {
      setState(() {
        _summary = summary;
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    await SummaryStorageService.delete(widget.transcription.id);
    await _generate();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      body: _loading ? _buildLoading() : _buildSummary(),
    );
  }

  // ── Loading ──
  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, _) {
                final s = 0.8 + _pulseController.value * 0.4;
                return Transform.scale(
                  scale: s,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        NotitiaTheme.neonPink.withValues(alpha: 0.6),
                        NotitiaTheme.neonPink.withValues(alpha: 0.0),
                      ]),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: NotitiaTheme.neonPink, size: 36),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(_statusText,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 15, color: NotitiaTheme.white)),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: NotitiaTheme.darkBlue,
                color: NotitiaTheme.neonPink,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary ──
  Widget _buildSummary() {
    final s = _summary!;
    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          backgroundColor: NotitiaTheme.darkBlue,
          pinned: true,
          expandedHeight: 140,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: NotitiaTheme.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: NotitiaTheme.neonCyan),
              tooltip: 'Regénérer',
              onPressed: _regenerate,
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NotitiaTheme.neonPink.withValues(alpha: 0.15),
                    NotitiaTheme.darkBlue,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 70, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome,
                        color: NotitiaTheme.neonPink, size: 16),
                    const SizedBox(width: 8),
                    Text('RÉSUMÉ INTELLIGENT',
                        style: GoogleFonts.orbitron(
                            fontSize: 10,
                            color: NotitiaTheme.neonPink,
                            letterSpacing: 3)),
                  ]),
                  const SizedBox(height: 8),
                  Text(s.title,
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: NotitiaTheme.white,
                          height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),

        // ── Top Key Figures (horizontal scroll) ──
        if (s.topFigures.isNotEmpty)
          SliverToBoxAdapter(child: _buildTopFigures(s.topFigures)),

        // ── Introduction ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(s.introduction,
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: NotitiaTheme.white.withValues(alpha: 0.9),
                    height: 1.65,
                    fontStyle: FontStyle.italic)),
          ),
        ),

        // ── Separator ──
        SliverToBoxAdapter(child: _neonSeparator()),

        // ── Sections ──
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _buildSection(s.sections[i], i),
            childCount: s.sections.length,
          ),
        ),

        // ── Footer ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.schedule,
                  size: 12,
                  color: NotitiaTheme.grey.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('Généré le ${_fmtDate(s.generatedAt)}',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: NotitiaTheme.grey.withValues(alpha: 0.6))),
            ]),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TOP FIGURES — Bandeau horizontal neon
  // ===========================================================================
  Widget _buildTopFigures(List<KeyFigure> figures) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        itemCount: figures.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final f = figures[i];
          final color = _chartColors[i % _chartColors.length];
          return Container(
            width: 130,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.15),
                  NotitiaTheme.darkBlue,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFromName(f.icon), color: color, size: 15),
                const SizedBox(height: 4),
                Text(f.value,
                    style: GoogleFonts.orbitron(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(f.label,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: NotitiaTheme.white.withValues(alpha: 0.7)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // SECTION
  // ===========================================================================
  Widget _buildSection(SummarySection section, int index) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Heading ──
          Row(children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: _chartColors[index % _chartColors.length],
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: _chartColors[index % _chartColors.length]
                        .withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(section.heading,
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: NotitiaTheme.white)),
            ),
          ]),
          const SizedBox(height: 14),

          // ── Visual (chart / flow / quote / key_figures) ──
          if (section.visual != null) ...[
            _buildVisual(section.visual!, index),
            const SizedBox(height: 16),
          ],

          // ── Image ──
          if (section.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: section.imageUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: NotitiaTheme.darkBlue,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: NotitiaTheme.neonPink.withValues(alpha: 0.2)),
                  ),
                  child: Center(
                      child: Icon(Icons.image_outlined,
                          color: NotitiaTheme.grey.withValues(alpha: 0.4),
                          size: 40)),
                ),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Content Markdown ──
          MarkdownBody(
            data: section.content,
            styleSheet: _mdStyle(),
            onTapLink: (_, href, _) {
              if (href != null) _openUrl(href);
            },
          ),

          // ── Sources ──
          if (section.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSources(section.sources),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // VISUAL DISPATCHER
  // ===========================================================================
  Widget _buildVisual(SectionVisual v, int sectionIdx) {
    switch (v.type) {
      case 'chart_bar':
        return _buildBarChart(v, sectionIdx);
      case 'chart_pie':
        return _buildPieChart(v, sectionIdx);
      case 'key_figures':
        return _buildKeyFiguresGrid(v.keyFigures, sectionIdx);
      case 'flow':
        return _buildFlowDiagram(v.flowSteps, sectionIdx);
      case 'quote':
        return _buildQuote(v.quote ?? '', v.quoteAuthor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // BAR CHART
  // ===========================================================================
  Widget _buildBarChart(SectionVisual v, int sectionIdx) {
    if (v.chartData.isEmpty) return const SizedBox.shrink();
    final maxVal =
        v.chartData.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.chartTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                const Icon(Icons.bar_chart_rounded,
                    color: NotitiaTheme.neonCyan, size: 16),
                const SizedBox(width: 8),
                Text(v.chartTitle!,
                    style: GoogleFonts.orbitron(
                        fontSize: 10,
                        color: NotitiaTheme.neonCyan,
                        letterSpacing: 2)),
              ]),
            ),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => NotitiaTheme.darkBlue,
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      return BarTooltipItem(
                        '${v.chartData[group.x.toInt()].label}\n${rod.toY.toStringAsFixed(0)}',
                        GoogleFonts.poppins(
                            fontSize: 11, color: NotitiaTheme.white),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (val, _) => Text(
                        val.toInt().toString(),
                        style: GoogleFonts.poppins(
                            fontSize: 9, color: NotitiaTheme.grey),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx >= v.chartData.length) {
                          return const SizedBox.shrink();
                        }
                        final label = v.chartData[idx].label;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label.length > 8
                                ? '${label.substring(0, 8)}…'
                                : label,
                            style: GoogleFonts.poppins(
                                fontSize: 9, color: NotitiaTheme.grey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: NotitiaTheme.grey.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                barGroups: v.chartData.asMap().entries.map((e) {
                  final color =
                      _chartColors[e.key % _chartColors.length];
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            color.withValues(alpha: 0.4),
                            color,
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PIE CHART
  // ===========================================================================
  Widget _buildPieChart(SectionVisual v, int sectionIdx) {
    if (v.chartData.isEmpty) return const SizedBox.shrink();
    final total = v.chartData.fold<double>(0, (s, e) => s + e.value);

    return _glassCard(
      child: Column(
        children: [
          if (v.chartTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.donut_large_rounded,
                    color: NotitiaTheme.neonCyan, size: 16),
                const SizedBox(width: 8),
                Text(v.chartTitle!,
                    style: GoogleFonts.orbitron(
                        fontSize: 10,
                        color: NotitiaTheme.neonCyan,
                        letterSpacing: 2)),
              ]),
            ),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                // Pie
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: v.chartData.asMap().entries.map((e) {
                        final color =
                            _chartColors[e.key % _chartColors.length];
                        final pct = total > 0
                            ? (e.value.value / total * 100)
                            : 0.0;
                        return PieChartSectionData(
                          color: color,
                          value: e.value.value,
                          title: '${pct.toStringAsFixed(0)}%',
                          titleStyle: GoogleFonts.orbitron(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: NotitiaTheme.white),
                          radius: 50,
                          titlePositionPercentageOffset: 0.55,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Legend
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: v.chartData.asMap().entries.map((e) {
                      final color =
                          _chartColors[e.key % _chartColors.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(e.value.label,
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: NotitiaTheme.white
                                        .withValues(alpha: 0.8)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // KEY FIGURES GRID
  // ===========================================================================
  Widget _buildKeyFiguresGrid(List<KeyFigure> figures, int sectionIdx) {
    if (figures.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: figures.asMap().entries.map((e) {
        final f = e.value;
        final color = _chartColors[(sectionIdx + e.key) % _chartColors.length];
        return Container(
          width: (MediaQuery.of(context).size.width - 50) / 2,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.12),
                NotitiaTheme.darkBlue.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFromName(f.icon), color: color, size: 20),
              const SizedBox(height: 8),
              Text(f.value,
                  style: GoogleFonts.orbitron(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color)),
              const SizedBox(height: 4),
              Text(f.label,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: NotitiaTheme.white.withValues(alpha: 0.7)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ===========================================================================
  // FLOW DIAGRAM (vertical steps)
  // ===========================================================================
  Widget _buildFlowDiagram(List<FlowStep> steps, int sectionIdx) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return _glassCard(
      child: Column(
        children: [
          Row(children: [
            const Icon(Icons.account_tree_rounded,
                color: NotitiaTheme.neonCyan, size: 16),
            const SizedBox(width: 8),
            Text('PROCESSUS',
                style: GoogleFonts.orbitron(
                    fontSize: 10,
                    color: NotitiaTheme.neonCyan,
                    letterSpacing: 2)),
          ]),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((e) {
            final step = e.value;
            final isLast = e.key == steps.length - 1;
            final color =
                _chartColors[(sectionIdx + e.key) % _chartColors.length];
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne verticale + cercle numéroté
                  SizedBox(
                    width: 36,
                    child: Column(children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [color, color.withValues(alpha: 0.5)],
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 10),
                          ],
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: GoogleFonts.orbitron(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: NotitiaTheme.white)),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  color.withValues(alpha: 0.5),
                                  color.withValues(alpha: 0.1),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  // Contenu de l'étape
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: NotitiaTheme.white)),
                          if (step.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(step.description,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: NotitiaTheme.white
                                        .withValues(alpha: 0.65),
                                    height: 1.5)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUOTE
  // ===========================================================================
  Widget _buildQuote(String quote, String? author) {
    if (quote.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            NotitiaTheme.neonPink.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
        border: Border(
          left: BorderSide(color: NotitiaTheme.neonPink, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('« $quote »',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: NotitiaTheme.white,
                  height: 1.55)),
          if (author != null && author.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('— $author',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: NotitiaTheme.neonPink.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // SHARED WIDGETS
  // ===========================================================================

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: NotitiaTheme.neonCyan.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }

  Widget _neonSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            NotitiaTheme.neonPink.withValues(alpha: 0.0),
            NotitiaTheme.neonPink.withValues(alpha: 0.5),
            NotitiaTheme.neonPink.withValues(alpha: 0.0),
          ]),
        ),
      ),
    );
  }

  Widget _buildSources(List<SummarySource> sources) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: NotitiaTheme.neonCyan.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.link_rounded,
                size: 14, color: NotitiaTheme.neonCyan),
            const SizedBox(width: 6),
            Text('SOURCES',
                style: GoogleFonts.orbitron(
                    fontSize: 9,
                    color: NotitiaTheme.neonCyan,
                    letterSpacing: 2)),
          ]),
          const SizedBox(height: 10),
          ...sources.map((src) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _openUrl(src.url),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.open_in_new,
                          size: 13,
                          color:
                              NotitiaTheme.neonPink.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(src.title,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: NotitiaTheme.neonPink,
                                    decoration: TextDecoration.underline,
                                    decorationColor: NotitiaTheme.neonPink
                                        .withValues(alpha: 0.4))),
                            if (src.snippet.isNotEmpty)
                              Text(src.snippet,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: NotitiaTheme.grey),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  MarkdownStyleSheet _mdStyle() {
    return MarkdownStyleSheet(
      p: GoogleFonts.poppins(
          fontSize: 14,
          color: NotitiaTheme.white.withValues(alpha: 0.85),
          height: 1.65),
      strong: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: NotitiaTheme.neonCyan),
      em: GoogleFonts.poppins(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: NotitiaTheme.white.withValues(alpha: 0.7)),
      h2: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: NotitiaTheme.white),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
              color: NotitiaTheme.neonPink.withValues(alpha: 0.5), width: 3),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        'à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
