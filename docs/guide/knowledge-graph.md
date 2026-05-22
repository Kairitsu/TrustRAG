# Knowledge Graph

TrustRAG extracts entities and relationships from your documents to build a knowledge graph. The graph visualization helps you explore connections across your knowledge base.

## Accessing the Knowledge Graph

1. Select a workspace from the sidebar
2. Navigate to the **Graph** tab in the main navigation
3. The graph loads automatically for the selected workspace

## Graph View

The interactive graph visualization shows:

- **Nodes** — Entities extracted from documents, color-coded by type
- **Edges** — Relationships between entities with labels and weights

### Entity Type Colors

| Type | Color |
|------|-------|
| Person | Blue |
| Organization | Purple |
| Location | Green |
| Concept/Topic | Orange |
| Event | Red |
| Document | Teal |
| Technology | Indigo |

### Interactions

- **Pan & Zoom** — Use scroll wheel or pinch to zoom, drag to pan
- **Click Node** — Select a node to see its details and related entities
- **Legend** — Shows entity type colors for the current graph

### Node Info Card

Clicking a node shows:
- Entity name and type
- Source document ID
- Related entities with relationship labels

## Entity List

Switch to the **Entity List** tab to browse all entities:

- **Search** — Filter entities by name or type
- **Grouped by Type** — Entities are organized by their type with color indicators
- **Count Summary** — Shows total entities and type count

## API Endpoints

- `GET /workspaces/{ws_id}/knowledge-graph` — Returns graph data (nodes + edges)
- `GET /workspaces/{ws_id}/knowledge-graph/entities` — Returns entity list with metadata
