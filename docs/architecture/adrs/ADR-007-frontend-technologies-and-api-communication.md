# ADR-007: Frontend Technologies and API Communication Strategy

**Status**: Proposed
**Date**: 2026-06-17
**Author**: Architecture Decision

---

## Context

Breakdown RS requires frontend applications for multiple platforms:
- **Web/Desktop**: Browser-based interface for desktop users (wardrobe managers, directors)
- **Mobile**: Tablet/mobile interface for on-set use (costume fittings, quick adjustments)

The backend uses **Event Sourcing with CQRS** (see ADR-002) and **PostgreSQL** (see ADR-003). This architectural choice fundamentally changes how the frontend communicates with the backend compared to traditional CRUD applications.

### Key Challenges

1. **Multi-Platform Frontend**: Need to support both web/desktop and mobile with shared backend
2. **Event Sourcing Communication**: Commands (write side) vs. Queries (read side) require different API patterns
3. **Type Safety Across Languages**: Rust backend types must stay in sync with TypeScript (Svelte) and Dart (Flutter)
4. **File Uploads**: Costume photos need efficient binary transfer (not JSON-embedded)
5. **Real-Time Updates**: Event-driven nature suggests potential for WebSocket/SSE integration

### Requirements

- Support SvelteKit for web/desktop frontend
- Support Flutter for mobile frontend
- Maintain type safety between backend and both frontends
- Handle Commands (write) and Queries (read) appropriately (CQRS)
- Efficient file upload for photos
- Fast read-model queries for responsive UI
- Minimize boilerplate and manual type synchronization

## Decision

We will use **SvelteKit (TypeScript)** for web/desktop and **Flutter (Dart)** for mobile, with **REST API + OpenAPI code generation** for type-safe communication.

### Frontend Technology Stack

| Platform | Technology | Language | Rationale |
|----------|-----------|----------|-----------|
| Web/Desktop | SvelteKit | TypeScript | Fast, reactive, excellent developer experience |
| Mobile | Flutter | Dart | Native performance, single codebase for iOS/Android |

### API Communication Strategy

```
┌─────────────────┐         OpenAPI Spec          ┌──────────────────┐
│  Rust Backend   │ ────────────────────────────> │  Code Generators │
│  (Axum + utoipa)│         (JSON)                │  (TypeScript/Dart)│
└─────────────────┘                                └──────────────────┘
        │                              ┌──────────────────────┬──────────────────────┐
        │ REST API                     │                      │                      │
        └──────────────────────────────>│   SvelteKit App     │   Flutter App        │
                                       │   (TypeScript)      │   (Dart)             │
                                       │   Generated Client  │   Generated Client   │
                                       └──────────────────────┴──────────────────────┘
```

### CQRS-Aware API Design

#### Write Side (Commands)
- **Endpoint Pattern**: `POST /api/v1/commands/{aggregate}/{action}`
- **Content Type**: `application/json` for Commands, `multipart/form-data` for file uploads
- **Response**: `202 Accepted` (async processing via Event Store)
- **Examples**:
  - `POST /api/v1/commands/scene/create`
  - `POST /api/v1/commands/costume/assign`
  - `POST /api/v1/commands/photo/add` (multipart)

#### Read Side (Queries)
- **Endpoint Pattern**: `GET /api/v1/{aggregate}/{id}` or `GET /api/v1/{aggregate}/list`
- **Content Type**: `application/json`
- **Response**: Flat, optimized DTOs from Read Models (Projections)
- **Examples**:
  - `GET /api/v1/dispo/{id}/gallery`
  - `GET /api/v1/production/{id}/scenes`
  - `GET /api/v1/costume/{id}/history`

### Why This Approach?

#### 1. OpenAPI Code Generation (Proven in ADR-006)
- ✅ **Type Safety**: Backend Rust types → OpenAPI Spec → Generated TypeScript/Dart
- ✅ **Compile-Time Errors**: Frontend fails to build if backend API changes
- ✅ **Single Source of Truth**: Rust types define the contract
- ✅ **Tooling**: Swagger UI for exploration, IDE auto-completion

#### 2. SvelteKit for Web/Desktop
- ✅ **Reactivity**: Built-in stores and reactive declarations
- ✅ **File-Based Routing**: Matches REST API structure intuitively
- ✅ **TypeScript-First**: Seamless integration with generated types
- ✅ **SSR/SSG**: Can pre-render static pages (wardrobe catalogs)

#### 3. Flutter for Mobile
- ✅ **Native Performance**: Compiled to native ARM code
- ✅ **Hot Reload**: Fast development cycle
- ✅ **Widget Library**: Material Design + Cupertino (iOS)
- ✅ **Dart OpenAPI Generators**: `openapi_generator_annotations` for type-safe clients

#### 4. CQRS-Aligned API Structure
- ✅ **Clear Separation**: Commands go to aggregates, Queries go to projections
- ✅ **Scalability**: Read models can be optimized independently
- ✅ **Eventual Consistency**: UI can handle async updates gracefully

## Consequences

### Positive
- ✅ **Type Safety Across Boundaries**: Rust → TypeScript/Dart compilation guarantees
- ✅ **Multi-Platform Support**: Separate optimized frontends for web and mobile
- ✅ **CQRS Compliance**: API structure enforces architectural patterns
- ✅ **Developer Experience**: Auto-generated clients, Swagger UI, IDE support
- ✅ **Performance**: Flat read models, efficient file uploads via multipart
- ✅ **Maintainability**: Single backend, generated frontends reduce drift

### Negative
- ⚠️ **Build Complexity**: Frontend builds depend on backend OpenAPI spec generation
- ⚠️ **Learning Curve**: Two frontend frameworks (Svelte and Flutter)
- ⚠️ **Code Generation Lock-in**: Tight coupling to OpenAPI generators
- ⚠️ **Eventual Consistency**: UI must handle stale data (read model lag)

### Mitigation
- **CI Pipeline**: Generate OpenAPI spec and frontend types in CI
- **Monorepo Structure**: Keep backend and frontend in sync with workspace tools
- **Error Boundaries**: Handle API version mismatches gracefully
- **Optimistic Updates**: UI updates immediately, reconciles with backend later

### Trade-offs
- **REST vs. GraphQL**: REST is simpler, GraphQL more flexible (but overkill for CQRS)
- **Generated vs. Hand-Written Clients**: Generated is type-safe, hand-written is more flexible
- **Svelte + Flutter vs. Single Framework**: Two frameworks = more maintenance, but better per-platform UX

## API Design Examples

### Command: Create Scene (Write Side)

**Request:**
```http
POST /api/v1/commands/scene/create
Content-Type: application/json

{
  "name": "Act 1, Scene 3",
  "description": "Romeo meets Juliet at the ball",
  "production_id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7I7"
}
```

**Response:**
```http
HTTP/1.1 202 Accepted
Content-Type: application/json

{
  "command_id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7I8",
  "status": "accepted",
  "links": {
    "self": "/api/v1/commands/status/01H8X7Y7Z7Q7W7E7R7T7Y7U7I8",
    "aggregate": "/api/v1/scenes/01H8X7Y7Z7Q7W7E7R7T7Y7U7I9"
  }
}
```

### Query: Get Scene List (Read Side)

**Request:**
```http
GET /api/v1/productions/01H8X7Y7Z7Q7W7E7R7T7Y7U7I7/scenes
Accept: application/json
```

**Response:**
```http
HTTP/1.1 200 OK
Content-Type: application/json

[
  {
    "id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7I9",
    "name": "Act 1, Scene 3",
    "description": "Romeo meets Juliet at the ball",
    "production_id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7I7",
    "costume_count": 5,
    "status": "draft",
    "updated_at": "2026-06-17T10:30:00Z"
  }
]
```

### Command: Upload Photo (Write Side with File Upload)

**Request:**
```http
POST /api/v1/commands/photo/add
Content-Type: multipart/form-data
Boundary: ----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="dispo_id"

01H8X7Y7Z7Q7W7E7R7T7Y7U7I9
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="metadata"

{"tags": ["fitting", "act1"]}
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="photo"; filename="costume_fitting.jpg"
Content-Type: image/jpeg

(二进制数据)
------WebKitFormBoundary7MA4YWxkTrZu0gW--
```

**Response:**
```http
HTTP/1.1 202 Accepted
Content-Type: application/json

{
  "command_id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7J0",
  "photo_id": "01H8X7Y7Z7Q7W7E7R7T7Y7U7J1",
  "status": "processing",
  "thumbnail_url": "/api/v1/photos/01H8X7Y7Z7Q7W7E7R7T7Y7U7J1/thumbnail"
}
```

## Frontend Code Generation Workflow

### Step 1: Generate OpenAPI Spec (Backend)

```bash
# Export OpenAPI spec from Rust backend
cargo run --bin breakdown-rs -- --export-openapi > openapi.json
```

### Step 2: Generate TypeScript Client (SvelteKit)

```bash
# Using openapi-typescript
npx openapi-typescript openapi.json -o frontend-svelte/src/lib/api/types.ts

# Or using openapi-generator (fetch client)
npx @openapitools/openapi-generator-cli generate \
  -i openapi.json \
  -g typescript-fetch \
  -o frontend-svelte/src/lib/api/generated \
  --additional-properties=modelPropertyNaming=original,supportsES6=true
```

**Generated TypeScript Example:**
```typescript
// frontend-svelte/src/lib/api/generated/scenes.ts"

export interface CreateSceneCommand {
  name: string;
  description?: string;
  production_id: string;
}

export interface SceneDto {
  id: string;
  name: string;
  description?: string;
  production_id: string;
  costume_count: number;
  status: 'draft' | 'active' | 'archived';
  updated_at: string;
}

export class ScenesApi {
  async createScene(cmd: CreateSceneCommand): Promise<CommandResponseDto> {
    const response = await fetch('/api/v1/commands/scene/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cmd),
    });
    return response.json();
  }

  async listScenes(productionId: string): Promise<SceneDto[]> {
    const response = await fetch(`/api/v1/productions/${productionId}/scenes`);
    return response.json();
  }
}
```

### Step 3: Generate Dart Client (Flutter)

```bash
# Using openapi_generator (Dart)
flutter pub run build_runner build --delete-conflicting-outputs

# Or using openapi-generator (Dart)
npx @openapitools/openapi-generator-cli generate \
  -i openapi.json \
  -g dart \
  -o frontend-flutter/lib/api/generated \
  --additional-properties=pubName=breakdown_api
```

**Generated Dart Example:**
```dart
// frontend-flutter/lib/api/generated/scenes_api.dart

class CreateSceneCommand {
  String name;
  String? description;
  String productionId;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'production_id': productionId,
  };
}

class ScenesApi {
  Future<CommandResponseDto> createScene(CreateSceneCommand cmd) async {
    final response = await http.post(
      Uri.parse('/api/v1/commands/scene/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(cmd.toJson()),
    );
    return CommandResponseDto.fromJson(jsonDecode(response.body));
  }

  Future<List<SceneDto>> listScenes(String productionId) async {
    final response = await http.get(
      Uri.parse('/api/v1/productions/$productionId/scenes'),
    );
    final List<dynamic> json = jsonDecode(response.body);
    return json.map((item) => SceneDto.fromJson(item)).toList();
  }
}
```

## SvelteKit Integration Example

```typescript
// frontend-svelte/src/routes/productions/[id]/scenes/+page.svelte
<script lang="ts">
  import { ScenesApi } from '$lib/api/generated/scenes';
  import type { SceneDto, CreateSceneCommand } from '$lib/api/generated/types';

  export let data: { productionId: string; scenes: SceneDto[] };

  const api = new ScenesApi();

  async function createScene() {
    const cmd: CreateSceneCommand = {
      name: $newSceneName,
      production_id: data.productionId,
    };

    // Send command (optimistic update)
    const response = await api.createScene(cmd);
    $newSceneName = '';

    // Poll or subscribe to read model update
    // (or use WebSocket for real-time update)
    setTimeout(() => refreshScenes(), 500);
  }

  async function refreshScenes() {
    data.scenes = await api.listScenes(data.productionId);
  }
</script>

<h1>Scenes</h1>
<ul>
  {#each data.scenes as scene (scene.id)}
    <li>{scene.name} - {scene.costume_count} costumes</li>
  {/each}
</ul>

<input bind:value={$newSceneName} placeholder="Scene name" />
<button on:click={createScene}>Create Scene</button>
```

## Flutter Integration Example

```dart
// frontend-flutter/lib/screens/scenes_screen.dart
import 'package:flutter/material.dart';
import 'api/generated/scenes_api.dart';
import 'api/generated/types.dart';

class ScenesScreen extends StatefulWidget {
  final String productionId;

  const ScenesScreen({Key? key, required this.productionId}) : super(key: key);

  @override
  _ScenesScreenState createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  final ScenesApi _api = ScenesApi();
  List<SceneDto> _scenes = [];
  String _newSceneName = '';

  @override
  void initState() {
    super.initState();
    _loadScenes();
  }

  Future<void> _loadScenes() async {
    final scenes = await _api.listScenes(widget.productionId);
    setState(() => _scenes = scenes);
  }

  Future<void> _createScene() async {
    final cmd = CreateSceneCommand()
      ..name = _newSceneName
      ..productionId = widget.productionId;

    // Send command
    await _api.createScene(cmd);

    // Optimistic update or refresh
    setState(() => _newSceneName = '');
    Future.delayed(Duration(milliseconds: 500), _loadScenes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scenes')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _scenes.length,
              itemBuilder: (context, index) {
                final scene = _scenes[index];
                return ListTile(
                  title: Text(scene.name),
                  subtitle: Text('${scene.costumeCount} costumes'),
                );
              },
            ),
          ),
          TextField(
            onChanged: (value) => setState(() => _newSceneName = value),
            decoration: InputDecoration(labelText: 'Scene name'),
          ),
          ElevatedButton(
            onPressed: _createScene,
            child: Text('Create Scene'),
          ),
        ],
      ),
    );
  }
}
```

## Alternatives Considered

### 1. Svelte + Tauri (Single Framework, Desktop-Only)

**Description**: Use SvelteKit for web, Tauri for desktop (bundles Svelte as native app).

**Pros**:
- ✅ Single frontend framework (Svelte only)
- ✅ Native performance on desktop (Tauri commands call Rust directly)
- ✅ No HTTP overhead for desktop app
- ✅ `specta` for type-safe Tauri commands

**Cons**:
- ❌ No mobile support (Tauri doesn't support iOS/Android yet)
- ❌ Two communication patterns (Tauri commands + HTTP REST)
- ❌ Limits future mobile expansion

**Why Not**: We need mobile support (tablets on set), and Tauri mobile is not production-ready.

### 2. Flutter Only (Single Framework, All Platforms)

**Description**: Use Flutter for web, desktop, and mobile.

**Pros**:
- ✅ Single framework for all platforms
- ✅ Single codebase (Dart only)
- ✅ Native performance on all platforms

**Cons**:
- ❌ Flutter web is heavy (large bundle size)
- ❌ SEO issues for public pages
- ❌ Less idiomatic web experience (no URL routing, etc.)
- ❌ Dart is less popular than TypeScript (hiring, ecosystem)

**Why Not**: Web/desktop needs SEO, fast initial load, and URL-based navigation. Flutter web is not optimal for this.

### 3. React Native + Next.js (JavaScript Ecosystem)

**Description**: Use Next.js for web, React Native for mobile.

**Pros**:
- ✅ Single language (TypeScript)
- ✅ Large ecosystem
- ✅ Easy to find developers

**Cons**:
- ❌ React Native performance (JavaScript bridge)
- ❌ Two frameworks to learn (Next.js + React Native)
- ❌ Less type-safe than Svelte/Flutter
- ❌ No native Dart/JS interop with Rust (need OpenAPI anyway)

**Why Not**: Flutter has better native performance, Svelte is more reactive and lighter.

### 4. GraphQL Instead of REST + OpenAPI

**Description**: Use GraphQL for all API communication.

**Pros**:
- ✅ Type-safe by default (GraphQL schema)
- ✅ Single endpoint
- ✅ Flexible queries (avoid over-fetching)

**Cons**:
- ❌ Doesn't map well to CQRS (Commands vs. Queries)
- ❌ Complex for file uploads (need separate endpoint anyway)
- ❌ Caching complexity (especially for mobile)
- ❌ Learning curve for team

**Why Not**: REST + OpenAPI is simpler, maps directly to CQRS, and file uploads are first-class. GraphQL is overkill for this use case.

### 5. gRPC Instead of REST

**Description**: Use gRPC for backend-frontend communication.

**Pros**:
- ✅ Type-safe by default (Protobuf)
- ✅ High performance (binary protocol)
- ✅ Code generation for all languages

**Cons**:
- ❌ Not natively supported by browsers (need gRPC-Web proxy)
- ❌ Harder to debug (binary protocol)
- ❌ No Swagger UI equivalent
- ❌ File uploads are awkward (need separate endpoint)

**Why Not**: Browser support is limited, and REST is more idiomatic for web. gRPC is better for backend-backend communication.

## Implementation Plan

### Phase 1: Backend OpenAPI Setup (Depends on ADR-006)

1. ✅ Implement `utoipa` in `crates/api` (ADR-006)
2. Define Command and Query DTOs in `crates/core`
3. Annotate handlers with `#[utoipa::path(...)]`
4. Serve OpenAPI spec at `/api-docs/openapi.json`

### Phase 2: SvelteKit Frontend (Web/Desktop)

1. Set up SvelteKit project in `frontend-svelte/`
2. Configure `openapi-typescript` or `openapi-generator`
3. Generate TypeScript types from OpenAPI spec
4. Implement first page (e.g., Scene list)
5. Set up CI to regenerate types on backend changes

### Phase 3: Flutter Frontend (Mobile)

1. Set up Flutter project in `frontend-flutter/`
2. Configure `openapi_generator_annotations` (Dart)
3. Generate Dart API client from OpenAPI spec
4. Implement first screen (e.g., Scene list)
5. Set up CI to regenerate client on backend changes

### Phase 4: File Upload Support

1. Implement `multipart/form-data` parsing in Axum
2. Store photos in object storage (S3/local filesystem)
3. Return `photo_id` immediately, process async (eventual consistency)
4. Update read models with photo metadata

### Phase 5: Real-Time Updates (Optional, Future)

1. Add WebSocket endpoint for event notifications
2. Frontend subscribes to aggregate changes
3. Auto-refresh read models on event
4. Consider Server-Sent Events (SSE) for simpler use case

## File Structure

```
breakdown-rs/
├── crates/
│   ├── core/              # DTOs, Commands, Queries (utoipa schemas)
│   ├── api/               # Axum handlers (utoipa annotations)
│   └── infra/             # Projections, Event Store
├── frontend-svelte/       # SvelteKit (TypeScript)
│   ├── src/
│   │   ├── lib/
│   │   │   └── api/
│   │   │       └── generated/  # Generated TypeScript types
│   │   └── routes/         # SvelteKit pages
│   └── package.json
├── frontend-flutter/      # Flutter (Dart)
│   ├── lib/
│   │   ├── api/
│   │   │   └── generated/  # Generated Dart client
│   │   └── screens/        # Flutter screens
│   └── pubspec.yaml
└── openapi.json           # Generated OpenAPI spec (gitignored or committed?)
```

## Dependencies

### Backend (Rust)
```toml
# crates/api/Cargo.toml
[dependencies]
axum = "0.7"
utoipa = { version = "4.0", features = ["axum_extras"] }
utoipa-axum = "4.0"
utoipa-swagger-ui = { version = "4.0", features = ["axum"] }
tokio = { version = "1.35", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
```

### Frontend SvelteKit (TypeScript)
```json
// frontend-svelte/package.json
{
  "devDependencies": {
    "openapi-typescript": "^6.0",
    "@openapitools/openapi-generator-cli": "^2.0"
  }
}
```

### Frontend Flutter (Dart)
```yaml
# frontend-flutter/pubspec.yaml
dependencies:
  http: ^1.1
  json_annotation: ^4.8

dev_dependencies:
  build_runner: ^2.4
  json_serializable: ^6.7
  openapi_generator_annotations: ^5.0
```

## Notes

### Best Practices

1. **CQRS Endpoint Naming**:
   - Commands: `POST /api/v1/commands/{aggregate}/{action}`
   - Queries: `GET /api/v1/{aggregate}` or `GET /api/v1/{parent}/{id}/{aggregate}`

2. **File Uploads**:
   - Use `multipart/form-data` for photos
   - Return immediately with `202 Accepted`
   - Process in background (Event Store → Projection)

3. **Error Handling**:
   - Commands: Return `400 Bad Request` for validation errors
   - Queries: Return `404 Not Found` if read model not found
   - Use Problem Details JSON (`application/problem+json`)

4. **Type Safety**:
   - Always generate frontend types from OpenAPI spec
   - Never manually type API responses
   - Use CI to validate OpenAPI spec generation

### Open Questions

1. **OpenAPI Spec Storage**: Commit to repo or generate on-demand?
   - *Recommendation*: Commit for frontend development without running backend
   - *Trade-off*: Spec can drift if not updated

2. **Authentication/Authorization**:
   - Not covered in this ADR (see future ADR on auth strategy)
   - Will likely use JWT tokens (Rust backend) + OAuth2 (Flutter native)

3. **Real-Time Updates**:
   - WebSocket vs. SSE vs. polling?
   - Event Sourcing makes WebSocket natural (subscribe to event stream)

4. **Offline Support (Mobile)**:
   - Flutter can cache read models locally
   - Commands can be queued offline (sync when online)

### Resources

- [SvelteKit Documentation](https://kit.svelte.dev/)
- [Flutter Documentation](https://docs.flutter.dev/)
- [utoipa Documentation](https://docs.rs/utoipa/latest/utoipa/)
- [openapi-typescript](https://github.com/drwpow/openapi-typescript)
- [openapi-generator](https://openapi-generator.tech/)
- [CQRS Pattern](https://martinfowler.com/bliki/CQRS.html)
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)

---

**Related ADRs**:
- [ADR-001: Use Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)
- [ADR-002: Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
- [ADR-005: Use Axum as Web Framework](./ADR-005-use-axum.md)
- [ADR-006: Use utoipa for OpenAPI Specification and Code Generation](./ADR-006-utoipa-openapi-codegen.md)

**Next Steps**:
1. Review and accept this ADR
2. Implement Phase 1 (OpenAPI setup, depends on ADR-006)
3. Prototype SvelteKit frontend (Phase 2)
4. Prototype Flutter frontend (Phase 3)
5. Document frontend patterns in `AGENTS.md`

**Status**: This ADR is ready for review. It builds on ADR-006 (utoipa) and provides the frontend architecture to consume the OpenAPI spec. Once accepted, we will proceed with implementation.
