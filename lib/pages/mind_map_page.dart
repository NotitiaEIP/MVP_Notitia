// =============================================================================
// NOTITIA — Page Mind Map
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mind_map.dart';
import '../models/transcription.dart';
import '../services/mind_map_service.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/mind_map_widget.dart';

class MindMapPage extends StatefulWidget {
  final Transcription? transcription;
  final ValueNotifier<int>? refreshNotifier;
  
  const MindMapPage({super.key, this.transcription, this.refreshNotifier});
  
  @override
  State<MindMapPage> createState() => _MindMapPageState();
}

class _MindMapPageState extends State<MindMapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  final MindMapService _mindMapService = MindMapService();
  
  final TextEditingController _textController = TextEditingController();
  
  late TabController _tabController;
  
  bool _isLoading = false;
  MindMap? _currentMindMap;
  MindMapNode? _selectedNode;
  String? _errorMessage;
  
  List<Transcription> _transcriptions = [];
  Transcription? _selectedTranscription;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadTranscriptions();
    
    // Si une transcription est passée, la sélectionner
    if (widget.transcription != null) {
      _selectedTranscription = widget.transcription;
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
  
  Future<void> _generateMindMap() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    MindMapResult result;
    
    if (_tabController.index == 0 && _selectedTranscription != null) {
      // Générer depuis une transcription
      result = await _mindMapService.generateFromTranscription(_selectedTranscription!);
    } else if (_tabController.index == 1 && _textController.text.isNotEmpty) {
      // Générer depuis du texte brut
      result = await _mindMapService.generateFromText(_textController.text);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Veuillez sélectionner une transcription ou entrer du texte';
      });
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
  }
  
  void _showNodeDetails(MindMapNode node) {
    setState(() {
      _selectedNode = node;
    });
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: NotitiaTheme.darkBlue,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: node.type.color.withOpacity(0.5)),
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
                    color: node.type.color.withOpacity(0.2),
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
                        style: TextStyle(
                          color: node.type.color,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Priorité
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(node.priority).withOpacity(0.2),
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
                  color: NotitiaTheme.deepBlue.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  node.description!,
                  style: const TextStyle(color: NotitiaTheme.white),
                ),
              ),
            ],
            
            // Tags
            if (node.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: node.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getTagColor(tag).withOpacity(0.2),
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
                )).toList(),
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
      case 5: return Colors.red;
      case 4: return Colors.orange;
      case 3: return Colors.yellow;
      case 2: return Colors.blue;
      default: return Colors.grey;
    }
  }
  
  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'urgent': return Colors.red;
      case 'important': return Colors.orange;
      case 'todo': return Colors.blue;
      case 'done': return Colors.green;
      case 'blocked': return Colors.purple;
      case 'idea': return Colors.yellow;
      case 'followup': return Colors.cyan;
      default: return Colors.grey;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NotitiaTheme.deepBlue,
      appBar: _buildAppBar(),
      body: _currentMindMap != null
          ? _buildMindMapView()
          : _buildSourceSelector(),
      floatingActionButton: _buildFAB(),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: NotitiaTheme.darkBlue,
      elevation: 0,
      title: Row(
        children: [
          Icon(
            Icons.account_tree,
            color: NotitiaTheme.neonCyan,
          ),
          const SizedBox(width: 12),
          const Text(
            'Mind Map',
            style: TextStyle(
              color: NotitiaTheme.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_currentMindMap != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: NotitiaTheme.neonPink.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentMindMap!.totalNodes} nœuds',
                style: const TextStyle(
                  color: NotitiaTheme.neonPink,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Bouton Rafraîchir transcriptions
        if (_currentMindMap == null)
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: NotitiaTheme.neonCyan,
            ),
            tooltip: 'Rafraîchir les transcriptions',
            onPressed: _loadTranscriptions,
          ),
        // Bouton Reset
        if (_currentMindMap != null)
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: NotitiaTheme.grey,
            ),
            tooltip: 'Nouvelle mind map',
            onPressed: () {
              setState(() {
                _currentMindMap = null;
                _selectedNode = null;
              });
            },
          ),
      ],
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
              Tab(
                icon: Icon(Icons.history),
                text: 'Transcription',
              ),
              Tab(
                icon: Icon(Icons.edit),
                text: 'Texte libre',
              ),
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
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.5)),
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
              color: NotitiaTheme.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune transcription disponible',
              style: TextStyle(
                color: NotitiaTheme.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Commencez par enregistrer une transcription',
              style: TextStyle(color: NotitiaTheme.grey),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transcriptions.length,
      itemBuilder: (context, index) {
        final transcription = _transcriptions[index];
        final isSelected = _selectedTranscription?.id == transcription.id;
        
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedTranscription = transcription;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected 
                  ? NotitiaTheme.neonCyan.withOpacity(0.1)
                  : NotitiaTheme.darkBlue,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected 
                    ? NotitiaTheme.neonCyan 
                    : NotitiaTheme.grey.withOpacity(0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.mic,
                      color: isSelected 
                          ? NotitiaTheme.neonCyan 
                          : NotitiaTheme.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        transcription.title,
                        style: TextStyle(
                          color: NotitiaTheme.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
    );
  }
  
  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: NotitiaTheme.white),
              decoration: InputDecoration(
                hintText: 'Collez ou tapez votre texte ici...\n\nLe système analysera le contenu et générera une mind map structurée avec les thèmes principaux, idées, actions et questions identifiées.',
                hintStyle: TextStyle(color: NotitiaTheme.grey.withOpacity(0.5)),
                filled: true,
                fillColor: NotitiaTheme.darkBlue,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: NotitiaTheme.grey.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: NotitiaTheme.grey.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: NotitiaTheme.neonCyan),
                ),
              ),
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _textController.text = data!.text!;
                  }
                },
                icon: const Icon(Icons.paste, color: NotitiaTheme.grey),
                label: const Text(
                  'Coller',
                  style: TextStyle(color: NotitiaTheme.grey),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _textController.clear(),
                icon: const Icon(Icons.clear, color: NotitiaTheme.grey),
                label: const Text(
                  'Effacer',
                  style: TextStyle(color: NotitiaTheme.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMindMapView() {
    return Stack(
      children: [
        // Mind Map
        MindMapWidget(
          mindMap: _currentMindMap!,
          onNodeTap: _showNodeDetails,
        ),
        
        // Info overlay
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: NotitiaTheme.darkBlue.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NotitiaTheme.neonCyan.withOpacity(0.5)),
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
                Text(
                  'Profondeur: ${_currentMindMap!.maxDepth} • Nœuds: ${_currentMindMap!.totalNodes}',
                  style: const TextStyle(
                    color: NotitiaTheme.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        

      ],
    );
  }
  
  Widget _buildFAB() {
    if (_currentMindMap != null) return const SizedBox.shrink();
    
    final canGenerate = (_tabController.index == 0 && _selectedTranscription != null) ||
                        (_tabController.index == 1 && _textController.text.isNotEmpty);
    
    return FloatingActionButton.extended(
      onPressed: _isLoading ? null : _generateMindMap,
      backgroundColor: canGenerate 
          ? NotitiaTheme.neonCyan 
          : NotitiaTheme.grey.withOpacity(0.5),
      icon: _isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NotitiaTheme.deepBlue,
              ),
            )
          : Icon(
              Icons.auto_awesome,
              color: NotitiaTheme.deepBlue,
            ),
      label: Text(
        _isLoading ? 'Génération...' : 'Générer Mind Map',
        style: TextStyle(
          color: NotitiaTheme.deepBlue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
