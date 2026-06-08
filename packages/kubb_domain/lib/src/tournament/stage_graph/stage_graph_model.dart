/// Stage-graph domain model (ADR-0030 §Modell): immutable, serializable nodes,
/// edges, routing selectors and the graph itself with read-only lookups.
///
/// Layer 1a: data model + serialization + lookups only. No runner, no semantic
/// validation, no templates, no persistence.
library;

export 'edge_selector.dart';
export 'stage_edge.dart';
export 'stage_graph.dart';
export 'stage_node.dart';
export 'stage_routing.dart';
