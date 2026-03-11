// =============================================================================
// NOTITIA — Page Mind Map
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mind_map.dart';
import '../models/transcription.dart';
import '../services/language_service.dart';
import '../services/mind_map_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/mind_map_widget.dart';
import '../widgets/meduza_widget.dart';
import '../widgets/meduza_speech_bubble.dart';
import '../widgets/page_header.dart';
import '../services/auth_service.dart';

class MindMapPage extends StatefulWidget {
  final Transcription? transcription;
  final ValueNotifier<int>? refreshNotifier;
  final void Function(MeduzaState state, {String? message, BubbleStyle style})?
  onMeduzaStateChanged;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;

  const MindMapPage({
    super.key,
    this.transcription,
    this.refreshNotifier,
    this.onMeduzaStateChanged,
    this.profile,
    this.onProfileTap,
  });

  @override
  State<MindMapPage> createState() => _MindMapPageState();
}

class _MindMapPageState extends State<MindMapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MindMapService _mindMapService = MindMapService();
  final LanguageService _languageService = LanguageService();

  final TextEditingController _textController = TextEditingController();

  late TabController _tabController;

  bool _isLoading = false;
  MindMap? _currentMindMap;
  String? _errorMessage;
  MindMapEngine? _selectedEngine;
  MindMapViewMode _viewMode = MindMapViewMode.radial;

  List<Transcription> _transcriptions = [];
  final Set<String> _selectedTranscriptionIds = {};

  // Saved mind maps
  List<MindMap> _savedMindMaps = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {}); // Rebuild FAB visibility on tab change
    });
    _loadTranscriptions();
    _loadSavedMindMaps();

    // Si une transcription est passée, la sélectionner
    if (widget.transcription != null) {
      _selectedTranscriptionIds.add(widget.transcription!.id);
    }

    // Écouter les nouvelles transcriptions
    widget.refreshNotifier?.addListener(_loadTranscriptions);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTranscriptions();
    }
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadTranscriptions);
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadTranscriptions() async {
    // Invalider le cache pour avoir les dernières transcriptions
    StorageService.invalidateCache();
    final transcriptions = await StorageService.loadAll();
    if (mounted) {
      setState(() {
        _transcriptions = transcriptions;
      });
    }
    debugPrint('📋 MindMap: ${transcriptions.length} transcriptions chargées');
  }

  Future<void> _loadSavedMindMaps() async {
    StorageService.invalidateMindMapsCache();
    final mindMaps = await StorageService.loadAllMindMaps();
    if (mounted) {
      setState(() {
        _savedMindMaps = mindMaps;
      });
    }
    debugPrint('📋 MindMap: ${mindMaps.length} mind maps sauvegardées');
  }

  /// Sauvegarde la mind map courante
  Future<void> _saveCurrentMindMap() async {
    if (_currentMindMap == null) return;
    await StorageService.saveMindMap(_currentMindMap!);
    await _loadSavedMindMaps();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Mind map « ${_currentMindMap!.title} » sauvegardée',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          backgroundColor: NotitiaTheme.darkBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  /// Charge une mind map sauvegardée
  void _openSavedMindMap(MindMap mindMap) {
    final engine = mindMap.metadata['engine'] as String?;
    setState(() {
      _currentMindMap = mindMap;
      _selectedEngine = engine == 'gemini'
          ? MindMapEngine.gemini
          : MindMapEngine.claude;
    });
  }

  /// Supprime une mind map sauvegardée
  Future<void> _deleteSavedMindMap(MindMap mindMap) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NotitiaTheme.darkBlue,
        title: Text(
          _languageService.translate('delete_mindmap_title'),
          style: const TextStyle(color: NotitiaTheme.white),
        ),
        content: Text(
          '« ${mindMap.title} » ${_languageService.translate('mindmap_delete_confirm')}',
          style: const TextStyle(color: NotitiaTheme.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _languageService.translate('cancel'),
              style: const TextStyle(color: NotitiaTheme.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _languageService.translate('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.deleteMindMap(mindMap.id);
      await _loadSavedMindMaps();
    }
  }

  /// Helper: get selected transcription objects
  List<Transcription> get _selectedTranscriptions {
    return _transcriptions
        .where((t) => _selectedTranscriptionIds.contains(t.id))
        .toList();
  }

  /// Affiche le choix du moteur puis lance la génération
  Future<void> _showEnginePickerAndGenerate() async {
    final engine = await showModalBottomSheet<MindMapEngine>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildEnginePicker(ctx),
    );

    if (engine == null) return; // Annulé
    _generateMindMap(engine);
  }

  Future<void> _generateMindMap(MindMapEngine engine) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedEngine = engine;
    });

    // Meduza - generation en cours
    widget.onMeduzaStateChanged?.call(
      MeduzaState.processing,
      message: _languageService.translate('generating_mindmap'),
    );

    MindMapResult result;

    if (_tabController.index == 0 && _selectedTranscriptionIds.isNotEmpty) {
      result = await _mindMapService.generateFromTranscriptions(
        _selectedTranscriptions,
        engine: engine,
      );
    } else if (_tabController.index == 1 && _textController.text.isNotEmpty) {
      result = await _mindMapService.generateFromText(
        _textController.text,
        engine: engine,
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Veuillez sélectionner au moins une transcription ou entrer du texte';
      });
      widget.onMeduzaStateChanged?.call(MeduzaState.idle);
      return;
    }

    setState(() {
      _isLoading = false;
      if (result.success) {
        _currentMindMap = result.mindMap;
        _errorMessage = null;
      } else {
        _errorMessage = result.error;
      }
    });

    // Auto-save après génération réussie
    if (result.success && _currentMindMap != null) {
      await _saveCurrentMindMap();
    }

    // Meduza - resultat
    if (result.success) {
      widget.onMeduzaStateChanged?.call(
        MeduzaState.happy,
        message: _languageService.translate('mindmap_generated_success'),
        style: BubbleStyle.success,
      );
    } else {
      widget.onMeduzaStateChanged?.call(
        MeduzaState.confused,
        message: _languageService.translate('error_generation_retry'),
        style: BubbleStyle.error,
      );
    }
  }

  Widget _buildEnginePicker(BuildContext ctx) {
    return Container(
      decoration: BoxDecoration(
        color: NotitiaTheme.darkBlue,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: NotitiaTheme.neonCyan.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NotitiaTheme.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _languageService.translate('choose_ai_engine'),
            style: const TextStyle(
              color: NotitiaTheme.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Option Gemini — Gratuit
          _buildEngineOption(
            ctx: ctx,
            engine: MindMapEngine.gemini,
            icon: Icons.auto_awesome,
            color: Colors.blueAccent,
            title: _languageService.translate('engine_gemini_label'),
            subtitle: _languageService.translate('free_label'),
            description: _languageService.translate('gemini_description'),
            badge: _languageService.translate('free_badge'),
            badgeColor: Colors.green,
          ),
          const SizedBox(height: 12),

          // Option Claude — Premium
          _buildEngineOption(
            ctx: ctx,
            engine: MindMapEngine.claude,
            icon: Icons.diamond,
            color: NotitiaTheme.neonPink,
            title: _languageService.translate('engine_claude_sonnet_label'),
            subtitle: _languageService.translate('premium_label'),
            description: _languageService.translate('claude_description'),
            badge: _languageService.translate('premium_badge'),
            badgeColor: NotitiaTheme.neonPink,
          ),
        ],
      ),
    );
  }

  Widget _buildEngineOption({
    required BuildContext ctx,
    required MindMapEngine engine,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String description,
    required String badge,
    required Color badgeColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(ctx).pop(engine),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NotitiaTheme.deepBlue.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: NotitiaTheme.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(color: NotitiaTheme.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeDetails(MindMapNode node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: NotitiaTheme.darkBlue,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: node.type.color.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: node.type.color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: node.type.color),
                  ),
                  child: Icon(node.type.icon, color: node.type.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.label,
                        style: const TextStyle(
                          color: NotitiaTheme.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        node.type.label,
                        style: TextStyle(color: node.type.color, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                // Priorité
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(
                      node.priority,
                    ).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getPriorityColor(node.priority)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.priority_high,
                        color: _getPriorityColor(node.priority),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${node.priority}',
                        style: TextStyle(
                          color: _getPriorityColor(node.priority),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Description
            if (node.description != null && node.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NotitiaTheme.deepBlue.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  node.description!,
                  style: const TextStyle(color: NotitiaTheme.white),
                ),
              ),
            ],

            // Source text contextuel
            if (node.sourceText != null && node.sourceText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSourceTextSection(node.sourceText!),
            ],

            // Tags
            if (node.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: node.tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getTagColor(tag).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getTagColor(tag)),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            color: _getTagColor(tag),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],

            // Enfants
            if (node.children.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${node.children.length} sous-éléments',
                style: const TextStyle(color: NotitiaTheme.grey),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 5:
        return Colors.red;
      case 4:
        return Colors.orange;
      case 3:
        return Colors.yellow;
      case 2:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'important':
        return Colors.orange;
      case 'todo':
        return Colors.blue;
      case 'done':
        return Colors.green;
      case 'blocked':
        return Colors.purple;
      case 'idea':
        return Colors.yellow;
      case 'followup':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  /// Construit la section « Source Text » avec highlight contextuel
  Widget _buildSourceTextSection(String sourceText) {
    final allContent = _selectedTranscriptions
        .map((t) => t.content)
        .join('\n\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NotitiaTheme.neonCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: NotitiaTheme.neonCyan.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote, color: NotitiaTheme.neonCyan, size: 18),
              const SizedBox(width: 8),
              Text(
                _languageService.translate('source_passage_title'),
                style: const TextStyle(
                  color: NotitiaTheme.neonCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Texte source exact avec guillemets
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NotitiaTheme.deepBlue.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: NotitiaTheme.neonCyan, width: 3),
              ),
            ),
            child: Text(
              '« $sourceText »',
              style: TextStyle(
                color: NotitiaTheme.white.withValues(alpha: 0.95),
                fontStyle: FontStyle.italic,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          // Contexte dans la transcription (si trouvé)
          if (allContent.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildContextHighlight(allContent, sourceText),
          ],
        ],
      ),
    );
  }

  /// Cherche sourceText dans la transcription et affiche un extrait contextuel
  /// avec le passage surligné en cyan
  Widget _buildContextHighlight(String fullText, String sourceText) {
    final lowerFull = fullText.toLowerCase();
    final lowerSource = sourceText.toLowerCase();
    final index = lowerFull.indexOf(lowerSource);

    if (index == -1) {
      // Pas trouvé : essayer une correspondance partielle (premiers mots)
      final firstWords = sourceText.split(' ').take(4).join(' ').toLowerCase();
      final partialIndex = lowerFull.indexOf(firstWords);
      if (partialIndex == -1) {
        return const SizedBox.shrink(); // Rien trouvé du tout
      }
      // Afficher le contexte partiel
      return _buildContextWidget(
        fullText,
        partialIndex,
        partialIndex + firstWords.length,
      );
    }

    return _buildContextWidget(fullText, index, index + sourceText.length);
  }

  Widget _buildContextWidget(String fullText, int matchStart, int matchEnd) {
    // Extraire ~60 caractères de contexte avant/après
    const contextChars = 60;
    final contextStart = (matchStart - contextChars).clamp(0, fullText.length);
    final contextEnd = (matchEnd + contextChars).clamp(0, fullText.length);

    final before = fullText.substring(contextStart, matchStart);
    final matched = fullText.substring(matchStart, matchEnd);
    final after = fullText.substring(matchEnd, contextEnd);

    final prefix = contextStart > 0 ? '…' : '';
    final suffix = contextEnd < fullText.length ? '…' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: NotitiaTheme.deepBlue.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: NotitiaTheme.grey, fontSize: 11, height: 1.4),
          children: [
            TextSpan(text: '$prefix$before'),
            TextSpan(
              text: matched,
              style: TextStyle(
                color: NotitiaTheme.neonCyan,
                fontWeight: FontWeight.bold,
                backgroundColor: NotitiaTheme.neonCyan.withValues(alpha: 0.15),
              ),
            ),
            TextSpan(text: '$after$suffix'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            NotitiaPageHeader(
              icon: Icons.account_tree_rounded,
              title: 'MIND MAP',
              profile: widget.profile,
              onProfileTap: widget.onProfileTap,
              actions: [
                if (_currentMindMap != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NotitiaTheme.neonPink.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _languageService
                          .translate('mindmap_nodes_label')
                          .replaceAll(
                            '{count}',
                            _currentMindMap!.totalNodes.toString(),
                          ),
                      style: const TextStyle(
                        color: NotitiaTheme.neonPink,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_currentMindMap == null)
                  IconButton(
                    icon: Icon(Icons.refresh, color: NotitiaTheme.neonCyan),
                    tooltip: _languageService.translate(
                      'refresh_transcriptions_tooltip',
                    ),
                    onPressed: _loadTranscriptions,
                  ),
                if (_currentMindMap != null)
                  IconButton(
                    icon: Icon(Icons.refresh, color: NotitiaTheme.grey),
                    tooltip: _languageService.translate('new_mindmap_tooltip'),
                    onPressed: () {
                      setState(() {
                        _currentMindMap = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _currentMindMap != null
                  ? _buildMindMapView()
                  : _buildSourceSelector(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildSourceSelector() {
    return Column(
      children: [
        // Tabs
        Container(
          color: NotitiaTheme.darkBlue,
          child: TabBar(
            controller: _tabController,
            indicatorColor: NotitiaTheme.neonCyan,
            labelColor: NotitiaTheme.neonCyan,
            unselectedLabelColor: NotitiaTheme.grey,
            tabs: const [
              Tab(icon: Icon(Icons.history), text: 'Transcriptions'),
              Tab(icon: Icon(Icons.edit), text: 'Texte libre'),
              Tab(icon: Icon(Icons.bookmark), text: 'Sauvegardées'),
            ],
          ),
        ),

        // Contenu
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTranscriptionSelector(),
              _buildTextInput(),
              _buildSavedMindMapsList(),
            ],
          ),
        ),

        // Message d'erreur
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTranscriptionSelector() {
    if (_transcriptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_off,
              size: 64,
              color: NotitiaTheme.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _languageService.translate('no_transcriptions_available'),
              style: TextStyle(color: NotitiaTheme.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _languageService.translate('start_with_transcription_hint'),
              style: TextStyle(color: NotitiaTheme.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Selection info bar
        if (_selectedTranscriptionIds.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: NotitiaTheme.neonCyan.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: NotitiaTheme.neonCyan,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _languageService
                      .translate('transcription_selected_count')
                      .replaceAll(
                        '{count}',
                        _selectedTranscriptionIds.length.toString(),
                      ),
                  style: const TextStyle(
                    color: NotitiaTheme.neonCyan,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () =>
                      setState(() => _selectedTranscriptionIds.clear()),
                  child: Text(
                    _languageService.translate('deselect_all'),
                    style: const TextStyle(
                      color: NotitiaTheme.grey,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16,
            ),
            itemCount: _transcriptions.length,
            itemBuilder: (context, index) {
              final transcription = _transcriptions[index];
              final isSelected = _selectedTranscriptionIds.contains(
                transcription.id,
              );

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedTranscriptionIds.remove(transcription.id);
                    } else {
                      _selectedTranscriptionIds.add(transcription.id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NotitiaTheme.neonCyan.withValues(alpha: 0.1)
                        : NotitiaTheme.darkBlue,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? NotitiaTheme.neonCyan
                          : NotitiaTheme.grey.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Checkbox visuelle
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? NotitiaTheme.neonCyan
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? NotitiaTheme.neonCyan
                                    : NotitiaTheme.grey.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: NotitiaTheme.deepBlue,
                                    size: 16,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              transcription.title,
                              style: TextStyle(
                                color: NotitiaTheme.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            transcription.formattedDate,
                            style: TextStyle(
                              color: NotitiaTheme.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        transcription.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: NotitiaTheme.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSavedMindMapsList() {
    if (_savedMindMaps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 64,
              color: NotitiaTheme.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _languageService.translate('no_saved_mindmaps'),
              style: TextStyle(color: NotitiaTheme.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _languageService.translate('generate_and_save_mindmap'),
              style: TextStyle(color: NotitiaTheme.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16),
      itemCount: _savedMindMaps.length,
      itemBuilder: (context, index) {
        final mindMap = _savedMindMaps[index];
        final engine = mindMap.metadata['engine'] as String? ?? 'unknown';
        final sourceCount = mindMap.sourceTranscriptionIds.length;
        final dateStr =
            '${mindMap.createdAt.day.toString().padLeft(2, '0')}/${mindMap.createdAt.month.toString().padLeft(2, '0')}/${mindMap.createdAt.year}';

        return GestureDetector(
          onTap: () => _openSavedMindMap(mindMap),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: NotitiaTheme.neonPink.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NotitiaTheme.neonPink.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_tree,
                        color: NotitiaTheme.neonPink,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mindMap.title,
                            style: const TextStyle(
                              color: NotitiaTheme.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dateStr • ${mindMap.totalNodes} nœuds • $sourceCount source${sourceCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: NotitiaTheme.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Engine badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: engine == 'claude'
                            ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
                            : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        engine == 'claude' ? 'Claude' : 'Gemini',
                        style: TextStyle(
                          color: engine == 'claude'
                              ? NotitiaTheme.neonPink
                              : Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Delete button
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: NotitiaTheme.grey.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      onPressed: () => _deleteSavedMindMap(mindMap),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                // Summary if available
                if (mindMap.metadata['summary'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    mindMap.metadata['summary'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: NotitiaTheme.grey, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextInput() {
    final canGenerate = _textController.text.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zone de texte — grandit avec le contenu
          TextField(
            controller: _textController,
            maxLines: null,
            minLines: 4,
            style: const TextStyle(color: NotitiaTheme.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _languageService.translate('paste_or_type_text_hint'),
              hintStyle: TextStyle(
                color: NotitiaTheme.grey.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: NotitiaTheme.darkBlue,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: NotitiaTheme.grey.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: NotitiaTheme.grey.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: NotitiaTheme.neonCyan),
              ),
            ),
            textAlignVertical: TextAlignVertical.top,
          ),
          const SizedBox(height: 12),
          // Barre d'actions + bouton Générer
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    setState(() => _textController.text = data!.text!);
                  }
                },
                icon: const Icon(
                  Icons.paste,
                  color: NotitiaTheme.grey,
                  size: 18,
                ),
                label: const Text(
                  'Coller',
                  style: TextStyle(color: NotitiaTheme.grey, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _textController.clear()),
                icon: const Icon(
                  Icons.clear,
                  color: NotitiaTheme.grey,
                  size: 18,
                ),
                label: const Text(
                  'Effacer',
                  style: TextStyle(color: NotitiaTheme.grey, fontSize: 13),
                ),
              ),
              AnimatedOpacity(
                opacity: canGenerate ? 1.0 : 0.45,
                duration: const Duration(milliseconds: 200),
                child: FilledButton.icon(
                  onPressed: _isLoading || !canGenerate
                      ? null
                      : _showEnginePickerAndGenerate,
                  style: FilledButton.styleFrom(
                    backgroundColor: NotitiaTheme.neonCyan,
                    foregroundColor: NotitiaTheme.deepBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NotitiaTheme.deepBlue,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _isLoading
                        ? _languageService.translate('generating_label')
                        : _languageService.translate(
                            'generate_mindmap_button_label',
                          ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMindMapView() {
    final isSaved = _savedMindMaps.any((m) => m.id == _currentMindMap!.id);

    return Stack(
      children: [
        // Mind Map
        MindMapWidget(
          mindMap: _currentMindMap!,
          onNodeTap: _showNodeDetails,
          viewMode: _viewMode,
        ),

        // Info overlay
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NotitiaTheme.neonCyan.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentMindMap!.title,
                  style: const TextStyle(
                    color: NotitiaTheme.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Profondeur: ${_currentMindMap!.maxDepth} • Nœuds: ${_currentMindMap!.totalNodes}',
                      style: const TextStyle(
                        color: NotitiaTheme.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedEngine == MindMapEngine.claude
                            ? NotitiaTheme.neonPink.withValues(alpha: 0.2)
                            : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedEngine == MindMapEngine.claude
                            ? _languageService.translate('engine_claude_badge')
                            : _languageService.translate('engine_gemini_badge'),
                        style: TextStyle(
                          color: _selectedEngine == MindMapEngine.claude
                              ? NotitiaTheme.neonPink
                              : Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_currentMindMap!.sourceTranscriptionIds.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_currentMindMap!.sourceTranscriptionIds.length} sources',
                    style: TextStyle(
                      color: NotitiaTheme.neonCyan.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Save button
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'save_mindmap',
            onPressed: isSaved ? null : _saveCurrentMindMap,
            backgroundColor: isSaved
                ? NotitiaTheme.grey.withValues(alpha: 0.3)
                : NotitiaTheme.neonPink,
            child: Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: isSaved ? NotitiaTheme.grey : NotitiaTheme.white,
            ),
          ),
        ),

        // View mode switcher
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NotitiaTheme.neonCyan.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: MindMapViewMode.values.map((mode) {
                final isActive = _viewMode == mode;
                return Tooltip(
                  message: _viewModeLabel(mode),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (_viewMode != mode) {
                        setState(() {
                          _viewMode = mode;
                        });
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? NotitiaTheme.neonCyan.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _viewModeIcon(mode),
                        color: isActive
                            ? NotitiaTheme.neonCyan
                            : NotitiaTheme.grey,
                        size: 20,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  IconData _viewModeIcon(MindMapViewMode mode) {
    switch (mode) {
      case MindMapViewMode.radial:
        return Icons.blur_circular;
      case MindMapViewMode.organigramme:
        return Icons.account_tree;
      case MindMapViewMode.horizontal:
        return Icons.swap_horiz;
    }
  }

  String _viewModeLabel(MindMapViewMode mode) {
    switch (mode) {
      case MindMapViewMode.radial:
        return _languageService.translate('view_mode_radial');
      case MindMapViewMode.organigramme:
        return _languageService.translate('view_mode_organigramme');
      case MindMapViewMode.horizontal:
        return _languageService.translate('view_mode_horizontal');
    }
  }

  Widget _buildFAB() {
    if (_currentMindMap != null) return const SizedBox.shrink();
    // Onglet Sauvegardées ou Texte libre : pas de FAB (bouton intégré dans la page)
    if (_tabController.index != 0) return const SizedBox.shrink();

    final canGenerate = _selectedTranscriptionIds.isNotEmpty;

    return FloatingActionButton.extended(
      onPressed: _isLoading ? null : _showEnginePickerAndGenerate,
      backgroundColor: canGenerate
          ? NotitiaTheme.neonCyan
          : NotitiaTheme.grey.withValues(alpha: 0.5),
      icon: _isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NotitiaTheme.deepBlue,
              ),
            )
          : Icon(Icons.auto_awesome, color: NotitiaTheme.deepBlue),
      label: Text(
        _isLoading
            ? _languageService.translate('generating_label')
            : _languageService.translate('generate_mindmap_button_label'),
        style: TextStyle(
          color: NotitiaTheme.deepBlue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
