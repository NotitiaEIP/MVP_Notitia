// =============================================================================
// NOTITIA — Widget Mind Map Interactif (Style Cyberpunk)
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mind_map.dart';
import '../theme.dart';

/// Widget principal pour afficher une Mind Map interactive
class MindMapWidget extends StatefulWidget {
  final MindMap mindMap;
  final Function(MindMapNode)? onNodeTap;
  final bool showLabels;
  final bool animateOnLoad;
  
  const MindMapWidget({
    super.key,
    required this.mindMap,
    this.onNodeTap,
    this.showLabels = true,
    this.animateOnLoad = true,
  });
  
  @override
  State<MindMapWidget> createState() => _MindMapWidgetState();
}

class _MindMapWidgetState extends State<MindMapWidget> 
    with SingleTickerProviderStateMixin {
  
  // Transformation pour pan/zoom
  final TransformationController _transformController = TransformationController();
  
  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  
  // Nœuds positionnés
  final List<_PositionedNode> _nodes = [];
  final List<_Connection> _connections = [];
  
  // Nœud sélectionné
  MindMapNode? _selectedNode;
  
  @override
  void initState() {
    super.initState();
    
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    
    if (widget.animateOnLoad) {
      _animController.forward();
    } else {
      _animController.value = 1.0;
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateLayout();
    });
  }
  
  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(MindMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mindMap != widget.mindMap) {
      _calculateLayout();
      if (widget.animateOnLoad) {
        _animController.reset();
        _animController.forward();
      }
    }
  }
  
  // Taille fixe du canvas
  static const double _canvasSize = 2000.0;
  static const double _canvasCenter = _canvasSize / 2;
  
  void _calculateLayout() {
    _nodes.clear();
    _connections.clear();
    
    // Utiliser le centre du canvas, pas de l'écran
    _layoutRadial(widget.mindMap.root, _canvasCenter, _canvasCenter, 0, 2 * math.pi, 0);
    
    setState(() {});
    
    // Auto-fit après le layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitToContent();
    });
  }
  
  void _fitToContent() {
    if (_nodes.isEmpty) return;
    
    // Calculer les limites de tous les nœuds
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    
    for (final node in _nodes) {
      minX = math.min(minX, node.x - 50);
      maxX = math.max(maxX, node.x + 50);
      minY = math.min(minY, node.y - 50);
      maxY = math.max(maxY, node.y + 50);
    }
    
    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    
    final viewSize = MediaQuery.of(context).size;
    
    // Calculer le scale pour tout voir avec marge
    final scaleX = (viewSize.width - 40) / contentWidth;
    final scaleY = (viewSize.height - 200) / contentHeight;
    final scale = math.min(scaleX, scaleY).clamp(0.3, 1.5);
    
    // Calculer le centre du contenu
    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;
    
    // Créer la transformation pour centrer et scaler
    final matrix = Matrix4.identity()
      ..translate(viewSize.width / 2, viewSize.height / 2)
      ..scale(scale)
      ..translate(-contentCenterX, -contentCenterY);
    
    _transformController.value = matrix;
  }
  
  void _layoutRadial(
    MindMapNode node,
    double x,
    double y,
    double startAngle,
    double endAngle,
    int depth,
  ) {
    // Ajouter le nœud actuel
    _nodes.add(_PositionedNode(node: node, x: x, y: y, depth: depth));
    
    if (node.children.isEmpty) return;
    
    // Calculer le rayon selon la profondeur - Plus grand pour meilleure lisibilité
    final radius = 180.0 + depth * 120.0;
    
    // Distribuer les enfants
    final angleStep = (endAngle - startAngle) / node.children.length;
    
    for (int i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final angle = startAngle + angleStep * (i + 0.5);
      
      final childX = x + radius * math.cos(angle);
      final childY = y + radius * math.sin(angle);
      
      // Ajouter la connexion
      _connections.add(_Connection(
        fromX: x,
        fromY: y,
        toX: childX,
        toY: childY,
        fromNode: node,
        toNode: child,
      ));
      
      // Récursion pour les enfants
      final childAngleSpread = angleStep * 0.9;
      _layoutRadial(
        child,
        childX,
        childY,
        angle - childAngleSpread / 2,
        angle + childAngleSpread / 2,
        depth + 1,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            NotitiaTheme.darkBlue.withOpacity(0.8),
            NotitiaTheme.deepBlue,
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(1000),
            minScale: 0.1,
            maxScale: 4.0,
            constrained: false,
            child: SizedBox(
              width: _canvasSize,
              height: _canvasSize,
              child: Stack(
                children: [
                  // Grille de fond cyberpunk
                  CustomPaint(
                    size: const Size(_canvasSize, _canvasSize),
                    painter: _CyberpunkGridPainter(
                      opacity: _fadeAnimation.value * 0.3,
                    ),
                  ),
                  
                  // Connexions (lignes)
                  ..._connections.map((conn) => _buildConnection(conn)),
                  
                  // Nœuds
                  ..._nodes.map((posNode) => _buildNode(posNode)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildConnection(_Connection conn) {
    final isHighlighted = _selectedNode == conn.fromNode || 
                          _selectedNode == conn.toNode;
    
    return Positioned(
      left: 0,
      top: 0,
      child: CustomPaint(
        size: const Size(_canvasSize, _canvasSize),
        painter: _ConnectionPainter(
          connection: conn,
          color: conn.toNode.type.color,
          opacity: _fadeAnimation.value * (isHighlighted ? 1.0 : 0.6),
          glowIntensity: isHighlighted ? 1.5 : 1.0,
        ),
      ),
    );
  }
  
  Widget _buildNode(_PositionedNode posNode) {
    final node = posNode.node;
    final isSelected = _selectedNode == node;
    final isRoot = node.type == MindMapNodeType.root;
    
    // Taille selon le type et la profondeur
    double size = isRoot ? 80 : 50 - posNode.depth * 5;
    size = size.clamp(30.0, 80.0);
    
    return Positioned(
      left: posNode.x - size / 2,
      top: posNode.y - size / 2,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _fadeAnimation,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedNode = isSelected ? null : node;
              });
              widget.onNodeTap?.call(node);
            },
            child: _MindMapNodeWidget(
              node: node,
              size: size,
              isSelected: isSelected,
              showLabel: widget.showLabels,
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget pour un nœud individuel
class _MindMapNodeWidget extends StatelessWidget {
  final MindMapNode node;
  final double size;
  final bool isSelected;
  final bool showLabel;
  
  const _MindMapNodeWidget({
    required this.node,
    required this.size,
    required this.isSelected,
    required this.showLabel,
  });
  
  @override
  Widget build(BuildContext context) {
    final color = node.type.color;
    final isRoot = node.type == MindMapNodeType.root;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nœud principal
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected 
                ? color 
                : NotitiaTheme.deepBlue.withOpacity(0.9),
            border: Border.all(
              color: color,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              // Glow effect
              BoxShadow(
                color: color.withOpacity(isSelected ? 0.8 : 0.5),
                blurRadius: isSelected ? 20 : 12,
                spreadRadius: isSelected ? 4 : 2,
              ),
              // Inner shadow
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              node.type.icon,
              color: isSelected ? NotitiaTheme.deepBlue : color,
              size: size * 0.5,
            ),
          ),
        ),
        
        // Label
        if (showLabel) ...[
          const SizedBox(height: 6),
          Container(
            constraints: BoxConstraints(maxWidth: isRoot ? 150 : 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NotitiaTheme.deepBlue.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Text(
              node.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NotitiaTheme.white,
                fontSize: isRoot ? 12 : 10,
                fontWeight: isRoot ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
        
        // Tags indicateurs
        if (node.tags.isNotEmpty && isSelected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              children: node.tags.take(3).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTagColor(tag).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }
  
  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'urgent': return Colors.red;
      case 'important': return Colors.orange;
      case 'todo': return Colors.blue;
      case 'done': return Colors.green;
      case 'blocked': return Colors.purple;
      default: return Colors.grey;
    }
  }
}

/// Painter pour les connexions avec effet néon
class _ConnectionPainter extends CustomPainter {
  final _Connection connection;
  final Color color;
  final double opacity;
  final double glowIntensity;
  
  _ConnectionPainter({
    required this.connection,
    required this.color,
    required this.opacity,
    this.glowIntensity = 1.0,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Calculer le point de contrôle pour la courbe de Bézier
    final midX = (connection.fromX + connection.toX) / 2;
    final midY = (connection.fromY + connection.toY) / 2;
    
    // Ajouter une courbure
    final dx = connection.toX - connection.fromX;
    final dy = connection.toY - connection.fromY;
    final perpX = -dy * 0.2;
    final perpY = dx * 0.2;
    
    final path = Path()
      ..moveTo(connection.fromX, connection.fromY)
      ..quadraticBezierTo(
        midX + perpX,
        midY + perpY,
        connection.toX,
        connection.toY,
      );
    
    // Glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.3 * glowIntensity)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    
    canvas.drawPath(path, glowPaint);
    
    // Ligne principale
    final linePaint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    canvas.drawPath(path, linePaint);
  }
  
  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) {
    return oldDelegate.opacity != opacity || 
           oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Painter pour la grille cyberpunk de fond
class _CyberpunkGridPainter extends CustomPainter {
  final double opacity;
  
  _CyberpunkGridPainter({required this.opacity});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NotitiaTheme.neonCyan.withOpacity(opacity * 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    const gridSize = 50.0;
    
    // Lignes verticales
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Lignes horizontales
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
    
    // Cercles concentriques au centre
    final center = Offset(size.width / 2, size.height / 2);
    final circlePaint = Paint()
      ..color = NotitiaTheme.neonPink.withOpacity(opacity * 0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    for (double r = 100; r < 600; r += 100) {
      canvas.drawCircle(center, r, circlePaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant _CyberpunkGridPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}

// ---------------------------------------------------------------------------
// Classes de données internes
// ---------------------------------------------------------------------------

class _PositionedNode {
  final MindMapNode node;
  final double x;
  final double y;
  final int depth;
  
  _PositionedNode({
    required this.node,
    required this.x,
    required this.y,
    required this.depth,
  });
}

class _Connection {
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final MindMapNode fromNode;
  final MindMapNode toNode;
  
  _Connection({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.fromNode,
    required this.toNode,
  });
}
