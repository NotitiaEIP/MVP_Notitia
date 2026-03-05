// =============================================================================
// NOTITIA — Widget Mind Map Interactif (Style Cyberpunk)
// Optimisé : un seul CustomPainter pour grille + connexions
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mind_map.dart';
import '../theme.dart';

/// Mode d'affichage de la Mind Map
enum MindMapViewMode {
  radial, // Vue circulaire/araignée (défaut)
  organigramme, // Vue arbre top-down
  horizontal, // Vue flux gauche→droite
}

/// Widget principal pour afficher une Mind Map interactive
class MindMapWidget extends StatefulWidget {
  final MindMap mindMap;
  final Function(MindMapNode)? onNodeTap;
  final bool showLabels;
  final bool animateOnLoad;
  final MindMapViewMode viewMode;

  const MindMapWidget({
    super.key,
    required this.mindMap,
    this.onNodeTap,
    this.showLabels = true,
    this.animateOnLoad = true,
    this.viewMode = MindMapViewMode.radial,
  });

  @override
  State<MindMapWidget> createState() => _MindMapWidgetState();
}

class _MindMapWidgetState extends State<MindMapWidget>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  final List<_PositionedNode> _nodes = [];
  final List<_Connection> _connections = [];

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
    if (oldWidget.mindMap != widget.mindMap ||
        oldWidget.viewMode != widget.viewMode) {
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

    switch (widget.viewMode) {
      case MindMapViewMode.radial:
        _layoutRadial(
          widget.mindMap.root,
          _canvasCenter,
          _canvasCenter,
          0,
          2 * math.pi,
          0,
        );
      case MindMapViewMode.organigramme:
        final subtreeWidth = _measureSubtreeWidth(widget.mindMap.root);
        _layoutOrganigramme(
          widget.mindMap.root,
          _canvasCenter - subtreeWidth / 2,
          _canvasCenter - 200,
          0,
        );
      case MindMapViewMode.horizontal:
        final subtreeHeight = _measureSubtreeHeight(widget.mindMap.root);
        _layoutHorizontal(
          widget.mindMap.root,
          _canvasCenter - 400,
          _canvasCenter - subtreeHeight / 2,
          0,
        );
    }

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitToContent();
    });
  }

  void _fitToContent() {
    if (_nodes.isEmpty || !mounted) return;

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

    // Sécurité : éviter division par zéro → matrice singulière → crash
    if (contentWidth < 1 || contentHeight < 1) return;

    final viewSize = MediaQuery.of(context).size;
    if (viewSize.width < 1 || viewSize.height < 1) return;

    final scaleX = (viewSize.width - 40) / contentWidth;
    final scaleY = (viewSize.height - 200) / contentHeight;
    final scale = math.min(scaleX, scaleY).clamp(0.15, 1.5);

    // Vérifier que le scale est valide (pas NaN/Inf)
    if (scale.isNaN || scale.isInfinite || scale <= 0) return;

    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(viewSize.width / 2, viewSize.height / 2, 0, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-contentCenterX, -contentCenterY, 0, 0);

    // Dernier check : la matrice doit être inversible
    final det = matrix.determinant();
    if (det.abs() < 1e-10) return;

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
    _nodes.add(_PositionedNode(node: node, x: x, y: y, depth: depth));

    if (node.children.isEmpty) return;

    final radius = 180.0 + depth * 120.0;
    final angleStep = (endAngle - startAngle) / node.children.length;

    for (int i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final angle = startAngle + angleStep * (i + 0.5);

      final childX = x + radius * math.cos(angle);
      final childY = y + radius * math.sin(angle);

      _connections.add(
        _Connection(
          fromX: x,
          fromY: y,
          toX: childX,
          toY: childY,
          fromNode: node,
          toNode: child,
        ),
      );

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

  // ===========================================================================
  // Layout Organigramme (top → down)
  // ===========================================================================
  static const double _orgaNodeSpacingX = 160.0;
  static const double _orgaLevelSpacingY = 180.0;

  double _measureSubtreeWidth(MindMapNode node) {
    if (node.children.isEmpty) return _orgaNodeSpacingX;
    double total = 0;
    for (final child in node.children) {
      total += _measureSubtreeWidth(child);
    }
    return math.max(total, _orgaNodeSpacingX);
  }

  double _layoutOrganigramme(
    MindMapNode node,
    double leftX,
    double y,
    int depth,
  ) {
    final subtreeW = _measureSubtreeWidth(node);
    final nodeX = leftX + subtreeW / 2;
    final nodeY = y;

    _nodes.add(_PositionedNode(node: node, x: nodeX, y: nodeY, depth: depth));

    if (node.children.isEmpty) return subtreeW;

    double childLeft = leftX;
    final childY = y + _orgaLevelSpacingY;

    for (final child in node.children) {
      final childW = _measureSubtreeWidth(child);
      _layoutOrganigramme(child, childLeft, childY, depth + 1);

      // Connexion parent → enfant
      final childNode = _nodes.lastWhere((n) => n.node == child);
      _connections.add(
        _Connection(
          fromX: nodeX,
          fromY: nodeY,
          toX: childNode.x,
          toY: childNode.y,
          fromNode: node,
          toNode: child,
        ),
      );

      childLeft += childW;
    }
    return subtreeW;
  }

  // ===========================================================================
  // Layout Horizontal (left → right)
  // ===========================================================================
  static const double _horizLevelSpacingX = 250.0;
  static const double _horizNodeSpacingY = 100.0;

  double _measureSubtreeHeight(MindMapNode node) {
    if (node.children.isEmpty) return _horizNodeSpacingY;
    double total = 0;
    for (final child in node.children) {
      total += _measureSubtreeHeight(child);
    }
    return math.max(total, _horizNodeSpacingY);
  }

  double _layoutHorizontal(MindMapNode node, double x, double topY, int depth) {
    final subtreeH = _measureSubtreeHeight(node);
    final nodeX = x;
    final nodeY = topY + subtreeH / 2;

    _nodes.add(_PositionedNode(node: node, x: nodeX, y: nodeY, depth: depth));

    if (node.children.isEmpty) return subtreeH;

    double childTop = topY;
    final childX = x + _horizLevelSpacingX;

    for (final child in node.children) {
      final childH = _measureSubtreeHeight(child);
      _layoutHorizontal(child, childX, childTop, depth + 1);

      final childNode = _nodes.lastWhere((n) => n.node == child);
      _connections.add(
        _Connection(
          fromX: nodeX,
          fromY: nodeY,
          toX: childNode.x,
          toY: childNode.y,
          fromNode: node,
          toNode: child,
        ),
      );

      childTop += childH;
    }
    return subtreeH;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            NotitiaTheme.darkBlue.withValues(alpha: 0.8),
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
                  // UN SEUL painter : grille + toutes les connexions
                  CustomPaint(
                    size: const Size(_canvasSize, _canvasSize),
                    painter: _BackgroundAndConnectionsPainter(
                      connections: _connections,
                      selectedNode: _selectedNode,
                      opacity: _fadeAnimation.value,
                    ),
                  ),

                  // Nœuds (widgets pour interactivité)
                  ..._nodes.map((posNode) => _buildNode(posNode)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNode(_PositionedNode posNode) {
    final node = posNode.node;
    final isSelected = _selectedNode == node;
    final isRoot = node.type == MindMapNodeType.root;

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

// =============================================================================
// Widget nœud individuel
// =============================================================================
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
    final hasSource = node.sourceText != null && node.sourceText!.isNotEmpty;

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
                : NotitiaTheme.deepBlue.withValues(alpha: 0.9),
            border: Border.all(color: color, width: isSelected ? 3 : 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isSelected ? 0.8 : 0.5),
                blurRadius: isSelected ? 20 : 12,
                spreadRadius: isSelected ? 4 : 2,
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                node.type.icon,
                color: isSelected ? NotitiaTheme.deepBlue : color,
                size: size * 0.5,
              ),
              // Indicateur sourceText (petit dot cyan en bas à droite)
              if (hasSource)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: NotitiaTheme.neonCyan,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: NotitiaTheme.deepBlue,
                        width: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Label
        if (showLabel) ...[
          const SizedBox(height: 6),
          Container(
            constraints: BoxConstraints(maxWidth: isRoot ? 150 : 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NotitiaTheme.deepBlue.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
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
              children: node.tags
                  .take(3)
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getTagColor(tag).withValues(alpha: 0.8),
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
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
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
      default:
        return Colors.grey;
    }
  }
}

// =============================================================================
// Painter unique : grille cyberpunk + TOUTES les connexions en un seul pass
// =============================================================================
class _BackgroundAndConnectionsPainter extends CustomPainter {
  final List<_Connection> connections;
  final MindMapNode? selectedNode;
  final double opacity;

  _BackgroundAndConnectionsPainter({
    required this.connections,
    required this.selectedNode,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintConnections(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridOpacity = opacity * 0.3;

    final paint = Paint()
      ..color = NotitiaTheme.neonCyan.withValues(alpha: gridOpacity * 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const gridSize = 50.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final circlePaint = Paint()
      ..color = NotitiaTheme.neonPink.withValues(alpha: gridOpacity * 0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (double r = 100; r < 600; r += 100) {
      canvas.drawCircle(center, r, circlePaint);
    }
  }

  void _paintConnections(Canvas canvas) {
    for (final conn in connections) {
      final isHighlighted =
          selectedNode == conn.fromNode || selectedNode == conn.toNode;
      final color = conn.toNode.type.color;
      final connOpacity = opacity * (isHighlighted ? 1.0 : 0.6);
      final glowIntensity = isHighlighted ? 1.5 : 1.0;

      final midX = (conn.fromX + conn.toX) / 2;
      final midY = (conn.fromY + conn.toY) / 2;
      final dx = conn.toX - conn.fromX;
      final dy = conn.toY - conn.fromY;
      final perpX = -dy * 0.2;
      final perpY = dx * 0.2;

      final path = Path()
        ..moveTo(conn.fromX, conn.fromY)
        ..quadraticBezierTo(midX + perpX, midY + perpY, conn.toX, conn.toY);

      // Glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha: connOpacity * 0.3 * glowIntensity)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path, glowPaint);

      // Ligne principale
      final linePaint = Paint()
        ..color = color.withValues(alpha: connOpacity)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundAndConnectionsPainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.connections.length != connections.length;
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
