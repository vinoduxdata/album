# Album Repository - Complete Architecture & User Flows Guide

> **Repository**: vinoduxdata/album  
> **Type**: Community fork of Immich (self-hosted photo/video management)  
> **Tech Stack**: NestJS (Backend), SvelteKit (Frontend), Flutter (Mobile), Python FastAPI (ML)  
> **License**: AGPL v3.0

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Core User Flows](#core-user-flows)
4. [Database Models](#database-models)
5. [Key Services & Features](#key-services--features)
6. [Fork-Specific Features](#fork-specific-features)

---

## Project Overview

**Album** is a **high-performance, self-hosted photo and video management solution** based on Immich v2.7.5. It's a monorepo containing:

- **Server**: NestJS 11 backend (TypeScript)
- **Web**: SvelteKit frontend with Svelte 5
- **Mobile**: Flutter/Dart app with Riverpod state management
- **Machine Learning**: Python FastAPI service (CLIP, facial recognition, OCR, YOLO pet detection)
- **CLI**: Command-line interface
- **OpenAPI**: SDK generation for TypeScript and Dart

### Key Capabilities

✅ Photo/Video upload, backup, and browsing  
✅ Multi-user support with role-based access  
✅ AI-powered search (CLIP embeddings)  
✅ Facial recognition and pet detection  
✅ Album management and sharing  
✅ S3-compatible storage support  
✅ Advanced filtering and smart search  
✅ Video editing and trimming  
✅ Shared Spaces (collaborative photo sharing)  

---

## Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────┐
���                    CLIENT LAYER                             │
├─────────────────┬──────────────┬──────────────┬─────────────┤
│   Web (SvelteKit)│ Mobile (Flutter) │ CLI (Node.js) │
└────────┬────────┴──────────┬───┴──────────────┴──────┬──────┘
         │                   │                         │
         │    REST API / Socket.IO                     │
         ▼                   ▼                         ▼
┌──────────────────────────────────────────────────────────────┐
│                  SERVER (NestJS)                            │
├──────────────────────────────────────────────────────────────┤
│  Controllers (HTTP Endpoints) → DTOs → Services             │
│  - AssetController, AlbumController, SearchController       │
│  - AuthController, UserController, SharedSpaceController    │
└──┬──────────────────────┬─────────────────────┬─────────────┘
   │                      │                     │
   ▼                      ▼                     ▼
┌──────────────────┐ ┌─────────────────┐ ┌────────────────────┐
│  Repositories    │ │  Job Queue      │ │  ML Service        │
│  (Data Access)   │ │  (BullMQ/Redis) │ │  (FastAPI/Python)  │
└──────────────────┘ └─────────────────┘ └────────────────────┘
   │
   ▼
┌──────────────────────────────────────────────────────────────┐
│         DATABASE (PostgreSQL + Extensions)                  │
│  - pgvectors/vectorchord (embeddings)                       │
│  - cube, earthdistance (geospatial)                         │
│  - pg_trgm (text search)                                    │
└──────────────────────────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────────────────────────┐
│         STORAGE LAYER                                        │
│  ├─ Local filesystem (Immich paths)                         │
│  ├─ S3-compatible storage (AWS S3, MinIO, Backblaze, etc.)  │
│  └─ Cloud backends                                          │
└──────────────────────────────────────────────────────────────┘
```

### Worker Architecture

The server runs **three separate worker types**:

| Worker | Purpose | Key Jobs |
|--------|---------|----------|
| **API Worker** | HTTP endpoint handling | Request/response processing |
| **Microservices Worker** | Background async jobs | Thumbnail generation, video encoding, ML tasks |
| **Maintenance Worker** | System maintenance | Database cleanup, duplicate detection, trash cleanup |

---

## Core User Flows

### 1. Asset Upload & Processing Flow

**User Action**: Upload a photo/video

**Flow Path**:
```
User (Web/Mobile)
    │
    ├─ POST /assets/upload
    ��
    ▼
AssetController.uploadFile()
    │ [Link: server/src/controllers/asset.controller.ts]
    │
    ├─ Validate file and auth
    │
    ├─ Store file (local or S3)
    │
    ├─ Create Asset DB record
    │   └─ [Table: asset.table.ts]
    │       - id, ownerId, fileSize, type (Image/Video)
    │       - status (Active, Archived, Trashed, Deleted)
    │
    ├─ Queue background jobs:
    │   ├─ AssetExtractMetadata
    │   │   └─ Extract EXIF, GPS, create exif record
    │   │       [Table: asset-exif.table.ts]
    │   │
    │   ├─ AssetGenerateThumbnails
    │   │   └─ Create thumbnail & preview files
    │   │       [AssetFileType: Thumbnail, Preview]
    │   │
    │   ├─ AssetDetectFaces (if ML enabled)
    │   │   └─ Facial recognition → Person records
    │   │       [Tables: person.table.ts, asset-face.table.ts]
    │   │
    │   ├─ AssetDetectObjects (if YOLO enabled)
    │   │   └─ Pet detection → Tags
    │   │
    │   └─ AssetGenerateClipEmbedding
    │       └─ Generate CLIP embedding for smart search
    │           [Table: smart-search.table.ts]
    │
    ▼
Response (Asset DTO)
```

**Relevant Code**:
- Controller: [`server/src/controllers/asset.controller.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/controllers/asset.controller.ts)
- Service: [`server/src/services/asset.service.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts)
- Repository: `server/src/repositories/asset.repository.ts`

---

### 2. Asset Browsing (Timeline/Gallery View)

**User Action**: View photos in timeline

**Flow Path**:
```
User clicks "Timeline"
    │
    ├─ GET /search/metadata
    │   [Link: server/src/controllers/search.controller.ts]
    │
    ▼
SearchService.searchMetadata(auth, dto)
    │ [Link: server/src/services/search.service.ts]
    │
    ├─ Determine user scope (self + partners if shared)
    │
    ├─ Query SearchRepository.searchMetadata()
    │   │
    │   ├─ Filter by:
    │   │   ├─ User ID(s)
    │   │   ├─ Visibility (Public, Private, Locked)
    │   │   ├─ Date range
    │   │   ├─ Asset type
    │   │   ├─ Albums/Spaces
    │   │   └─ Tags/People/Ratings
    │   │
    │   ├─ Paginate results (limit 250 default)
    │   │
    │   └─ Return MapAsset[] with relations:
    │       ├─ asset (id, filename, type, createdAt)
    │       ├─ exifInfo (GPS, camera, iso, etc.)
    │       ├─ faces (people detected)
    │       ├─ stack (grouped photos)
    │       └─ tags
    │
    ├─ Map to AssetResponseDto
    │
    ▼
Return paginated results to client

Client renders timeline
```

**Key Tables Involved**:
- [`asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset.table.ts) - Core asset
- [`asset-exif.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-exif.table.ts) - Metadata (GPS, camera)
- [`asset-face.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-face.table.ts) - Detected faces
- [`stack.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/stack.table.ts) - Stacked/grouped photos

**Relevant Code**:
- Service: [`server/src/services/search.service.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/services/search.service.ts)
- Controller: `server/src/controllers/search.controller.ts`

---

### 3. Smart Search Flow (CLIP-based)

**User Action**: Search "beach sunset"

**Flow Path**:
```
User enters search query
    │
    ├─ GET /search/smart?query=beach%20sunset
    │
    ▼
SearchService.searchSmart(auth, dto)
    │ [Link: server/src/services/search.service.ts]
    │
    ├─ Check ML config (must be enabled)
    │
    ├─ Encode query text to CLIP embedding:
    │   ├─ Check embedding cache (LRUMap)
    │   │
    │   ├─ If not cached:
    │   │   ├─ Send to ML service
    │   │   │   POST /ml/clip/text-encode
    │   │   │   {query: "beach sunset", modelName: "clip-vit-base-patch32"}
    │   │   │
    │   │   ├─ ML service returns embedding vector
    │   │   │
    │   │   └─ Cache result (up to 100 recent queries)
    │   │
    │   └─ Retrieve embedding vector
    │
    ├─ Handle Shared Spaces (if withSharedSpaces=true)
    │   └─ Get space IDs user has access to
    │
    ├─ Query database using vector similarity:
    │   ├─ SELECT assets WHERE
    │   │   ├─ owner in (user_ids)
    │   │   ├─ embedding <-> query_embedding < maxDistance
    │   │   ├─ visibility NOT Locked
    │   │   ├─ status = Active
    │   │   └─ LIMIT 100
    │   │
    │   └─ Return ranked results by similarity
    │
    ├─ Map to AssetResponseDto[]
    │
    ▼
Return search results (ranked by CLIP similarity)

Client displays results
```

**Key Tables**:
- [`smart-search.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/smart-search.table.ts) - CLIP embeddings
- [`asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset.table.ts) - Assets

**Relevant Code**:
- Service: [`server/src/services/search.service.ts#searchSmart`](https://github.com/vinoduxdata/album/blob/main/server/src/services/search.service.ts#L128-L222)

---

### 4. Album Creation & Asset Management

**User Action**: Create album and add assets

**Flow Path**:
```
User clicks "Create Album"
    │
    ├─ POST /albums
    │   {name: "Vacation 2024", description: "..."}
    │
    ▼
AlbumController.createAlbum(auth, dto)
    │ [Link: server/src/controllers/album.controller.ts]
    │
    ▼
AlbumService.create(auth, dto)
    │ [Link: server/src/services/album.service.ts]
    │
    ├─ Validate user permissions
    │
    ├─ Create Album record
    │   └─ [Table: album.table.ts]
    │       - id, ownerId, albumName, description, createdAt
    │
    ├─ (Optional) Add initial assets:
    │   │
    │   ├─ PUT /albums/{id}/assets
    │   │   {ids: ["asset1", "asset2", ...]}
    │   │
    │   └─ Create AlbumAsset join records
    │       └─ [Table: album-asset.table.ts]
    │           - albumId, assetId, order, createdAt
    │
    ├─ (Optional) Share with users:
    │   │
    │   ├─ PUT /albums/{id}/users
    │   │   {users: [{id: "user1", role: "Owner"}]}
    │   │
    │   └─ Create AlbumUser records
    │       └─ [Table: album-user.table.ts]
    │           - albumId, userId, role (Owner/Editor/Viewer)
    │
    ▼
Return AlbumResponseDto
    {id, albumName, description, assets: [...], users: [...]}
```

**Key Tables**:
- [`album.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album.table.ts) - Album definition
- [`album-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album-asset.table.ts) - Album membership
- [`album-user.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album-user.table.ts) - User access

**Relevant Code**:
- Controller: [`server/src/controllers/album.controller.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/controllers/album.controller.ts)
- Service: `server/src/services/album.service.ts`

---

### 5. Shared Spaces Flow (Fork-Specific)

**User Action**: Create collaborative shared space

**Flow Path**:
```
User clicks "Create Shared Space"
    │
    ├─ POST /shared-spaces
    │   {name: "Family Photos", description: "..."}
    │
    ▼
SharedSpaceController.create(auth, dto)
    │
    ▼
SharedSpaceService.create(auth, dto)
    │
    ├─ Create SharedSpace record
    │   └─ [Table: shared-space.table.ts]
    │       - id, ownerId, spaceName, createdAt
    │
    ├─ Add creator as member:
    │   │
    │   └─ [Table: shared-space-member.table.ts]
    │       - spaceId, userId, role (Owner/Admin/Member)
    │       - color, canUpload, canDelete, canComment
    │
    ├─ (Optional) Add members:
    │   │
    │   ├─ PUT /shared-spaces/{id}/members
    │   │   {members: [{id: "user1", role: "Member"}]}
    │   │
    │   └─ Create multiple SharedSpaceMember records
    │
    ├─ Members can upload to space:
    │   │
    │   ├─ PUT /shared-spaces/{id}/assets
    │   │   {assetIds: [...]}
    │   │
    │   └─ Create SharedSpaceAsset records
    │       └─ [Table: shared-space-asset.table.ts]
    │           - spaceId, assetId, uploadedBy, uploadedAt
    │
    ├─ Per-space person aliases:
    │   │
    │   └─ [Table: shared-space-person.table.ts]
    │       - Alternate names for people in this space
    │       - Example: "John Smith" → "Dad" in Family Space
    │
    ▼
Space ready for collaboration
```

**Key Tables**:
- [`shared-space.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space.table.ts)
- [`shared-space-member.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-member.table.ts)
- [`shared-space-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-asset.table.ts)
- [`shared-space-person.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-person.table.ts)

---

### 6. Facial Recognition & Person Management

**User Action**: View detected faces / manage people

**Flow Path**:
```
Asset uploaded
    │
    ├─ Job queued: AssetDetectFaces
    │
    ▼
ML Service processes image:
    ├─ Detect faces using InsightFace (ONNX)
    ├─ Generate 512-dim face embedding per face
    ├─ Return face list with embeddings
    │
    ▼
Server processes results:
    │
    ├─ For each detected face:
    │   │
    │   ├─ Cluster with existing faces:
    │   │   ├─ Query FaceSearchRepository
    │   │   ├─ Compare embedding similarity
    │   │   └─ Match to existing Person or create new
    │   │
    │   ├─ Create AssetFace record
    │   │   └─ [Table: asset-face.table.ts]
    │   │       - assetId, personId, x, y, width, height
    │   │       - embedding (512-dim vector)
    │   │       - confidence
    │   │
    │   └─ Update Person record (if merged)
    │       └─ [Table: person.table.ts]
    │           - id, ownerId, name, birthDate
    │           - thumbnailPath, isHidden
    │
    ├─ User can:
    │   │
    │   ├─ GET /people (view all recognized people)
    │   │
    │   ├─ GET /people/{id}/assets (see all photos with this person)
    │   │
    │   ├─ PATCH /people/{id} (rename, hide, merge people)
    │   │
    │   └─ PUT /face/{id} (confirm/reassign a face)
    │
    ▼
"People" section shows all recognized persons
```

**Key Tables**:
- [`person.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/person.table.ts) - Recognized person
- [`asset-face.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-face.table.ts) - Face bounding box + embedding
- [`face-search.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/face-search.table.ts) - Fast face lookup

---

### 7. Image Editing & Video Trimming (Fork-Specific)

**User Action**: Edit image or trim video

**Flow Path**:
```
User opens image in viewer
    │
    ├─ GET /assets/{id}
    │
    ├─ User clicks "Edit" → crop/rotate/mirror
    │   OR
    ├─ User clicks "Trim" (video only)
    │
    ▼
POST /assets/{id}/edits
    {edits: [{action: "Rotate", parameters: {degrees: 90}}]}
    OR
    {edits: [{action: "Trim", parameters: {startTime: 10, endTime: 45}}]}
    │
    ▼
AssetService.editAsset(auth, id, dto)
    │ [Link: server/src/services/asset.service.ts#L631-L750]
    │
    ├─ Validate asset exists and user has permission
    │
    ├─ Image validation:
    │   ├─ Not a live photo
    │   ├─ Not a panorama
    │   ├─ Not GIF/SVG
    │   └─ Dimensions available
    │
    ├─ Video trimming validation:
    │   ├─ Asset is video
    │   ├─ Video has video streams (not audio-only)
    │   ├─ Duration >= 2 seconds
    │   ├─ New times within bounds
    │   └─ Not a live photo
    │
    ├─ Store edit operations:
    │   │
    │   └─ [Table: asset-edit.table.ts]
    │       - assetId, action, parameters, createdAt
    │       - For trim: stores originalDuration
    │
    ├─ Queue background job:
    │   ├─ For images: AssetEditThumbnailGeneration
    │   │   └─ Apply edits, regenerate thumbnail
    │   │
    │   └─ For videos: AssetEditThumbnailGeneration
    │       └─ For trim, create new trimmed file
    │
    ▼
Return AssetEditsResponseDto
    {assetId, edits: [...]}
```

**Key Tables**:
- [`asset-edit.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-edit.table.ts)

**Relevant Code**:
- Service: [`server/src/services/asset.service.ts#editAsset`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts#L631-L750)

---

### 8. Asset Deletion Flow

**User Action**: Delete asset(s)

**Flow Path**:
```
User selects asset(s) and clicks Delete
    │
    ├─ DELETE /assets?ids=[...]
    │   OR force delete: ?force=true
    │
    ▼
AssetService.deleteAll(auth, dto)
    │ [Link: server/src/services/asset.service.ts#L450-L462]
    │
    ├─ Check user has delete permission
    │
    ├─ Update asset status:
    │   ├─ If force=false → status = "Trashed", deletedAt = now
    │   │   (Trash retention period: configurable)
    │   │
    │   └─ If force=true → status = "Deleted"
    │
    ├─ Emit events for real-time UI update
    │
    ▼
Background Job: AssetDeleteCheck (periodic, via maintenance worker)
    │
    ├─ Find assets in trash older than retention days
    │
    ├─ Queue AssetDelete jobs for each
    │
    ▼
Background Job: AssetDelete (per asset)
    │ [Link: server/src/services/asset.service.ts#L387-L448]
    │
    ├─ Update stack if needed (handle primary asset removal)
    │
    ├─ Remove asset from albums, shared links, spaces
    │
    ├─ Delete linked motion video if exists
    │
    ├─ Delete all asset files:
    │   ├─ Original file
    │   ├─ Thumbnail
    │   ├─ Preview
    │   ├─ Encoded video
    │   ├─ Edited versions
    │   └─ Sidecar (.xmp)
    │
    ├─ Decrement user storage usage
    │
    ├─ Emit AssetDelete event
    │
    ▼
Asset permanently removed from system
```

**Key Flow**:
- Service: [`server/src/services/asset.service.ts#handleAssetDeletionCheck`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts#L353-L385)
- Service: [`server/src/services/asset.service.ts#handleAssetDeletion`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts#L387-L448)

---

## Database Models

### Core Tables

#### Users & Authentication
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`user.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/user.table.ts) | User accounts | id, email, password, name, isAdmin, profileImagePath, quotaSizeInBytes |
| [`session.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/session.table.ts) | Auth sessions | id, userId, accessToken, expiresAt |
| [`api-key.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/api-key.table.ts) | API keys for CLI/SDK | id, userId, key, name, createdAt |

#### Assets & Media
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset.table.ts) | Core media file | id, ownerId, libraryId, originalPath, fileSize, type (Image/Video), duration, width, height, orientation, status (Active/Archived/Trashed/Deleted), visibility (Public/Private/Locked), isFavorite, rating, createdAt |
| [`asset-file.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-file.table.ts) | Multiple file variants | assetId, type (Original/Thumbnail/Preview/EncodedVideo/EditedFullsize/Sidecar), path, checksum |
| [`asset-exif.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-exif.table.ts) | EXIF metadata | assetId, description, dateTimeOriginal, latitude, longitude, country, state, city, make, model, lensModel, iso, focalLength, fNumber |
| [`asset-face.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-face.table.ts) | Detected faces | id, assetId, personId, x, y, width, height, embedding (512-dim vector), confidence |
| [`asset-edit.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-edit.table.ts) | Image/video edits | id, assetId, action (Rotate/Mirror/Crop/Trim), parameters (JSON) |
| [`asset-metadata.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-metadata.table.ts) | Custom key-value metadata | assetId, key, value |
| [`asset-ocr.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-ocr.table.ts) | OCR text extraction | id, assetId, text |
| [`stack.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/stack.table.ts) | Grouped assets (burst, panorama) | id, primaryAssetId |

#### Albums & Sharing
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`album.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album.table.ts) | Album collection | id, ownerId, albumName, description, createdAt, updatedAt |
| [`album-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album-asset.table.ts) | Album membership | albumId, assetId, order |
| [`album-user.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/album-user.table.ts) | Album sharing | albumId, userId, role (Owner/Editor/Viewer) |
| [`shared-link.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-link.table.ts) | Public share links | id, userId, key, type (Individual/Album), expiresAt, allowDownload, allowUpload, showExif |
| [`shared-link-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-link-asset.table.ts) | Individual asset shares | sharedLinkId, assetId |

#### Shared Spaces (Fork-Specific)
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`shared-space.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space.table.ts) | Collaborative space | id, ownerId, spaceName, description, color, createdAt |
| [`shared-space-member.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-member.table.ts) | Space membership | spaceId, userId, role (Owner/Admin/Editor/Viewer), color, canUpload, canDelete, canComment |
| [`shared-space-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-asset.table.ts) | Assets in space | spaceId, assetId, uploadedBy, uploadedAt |
| [`shared-space-library.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-library.table.ts) | Linked libraries | spaceId, libraryId, role (Owner/Viewer) |
| [`shared-space-person.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-person.table.ts) | Per-space person aliases | id, spaceId, personId, name (alternate) |
| [`shared-space-activity.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/shared-space-activity.table.ts) | Activity log | spaceId, userId, type, assetId, createdAt |

#### People & Recognition
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`person.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/person.table.ts) | Recognized person | id, ownerId, name, birthDate, thumbnailPath, isHidden, inceptionDate |
| [`partner.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/partner.table.ts) | Partner sharing | id, ownerId, sharedById, inTimeline, canCreate |

#### Search & ML
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`smart-search.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/smart-search.table.ts) | CLIP embeddings | assetId, embedding (1536-dim vector for smart search) |
| [`face-search.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/face-search.table.ts) | Fast face lookup | faceId, personId |
| [`ocr-search.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/ocr-search.table.ts) | OCR text search | id, assetId, text (full text search) |

#### Tags & Organization
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`tag.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/tag.table.ts) | User-defined tags | id, userId, name, color |
| [`tag-asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/tag-asset.table.ts) | Tag assignment | tagId, assetId |
| [`tag-closure.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/tag-closure.table.ts) | Tag hierarchy | ancestorId, descendantId, depth |
| [`user-group.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/user-group.table.ts) | User groups (Fork-specific) | id, userId, name, color |
| [`user-group-member.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/user-group-member.table.ts) | Group members (Fork-specific) | groupId, userId |

#### Jobs & Background Tasks
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`asset-job-status.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset-job-status.table.ts) | Job tracking | assetId, jobName, status (Success/Failed/Skipped) |

#### System & Audit
| Table | Purpose | Key Fields |
|-------|---------|-----------|
| [`system-metadata.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/system-metadata.table.ts) | System config | key, value |
| [`*-audit.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables) | Audit logs (multiple) | Records all changes to core entities for compliance |

---

## Key Services & Features

### Core Services

#### 1. **AssetService**
**File**: [`server/src/services/asset.service.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts)

**Responsibilities**:
- Asset retrieval, update, deletion
- Metadata management (EXIF, OCR)
- Bulk operations
- Image editing & video trimming
- Asset lifecycle (upload → processing → deletion)

**Key Methods**:
```typescript
async get(auth, id)                          // Get single asset with relations
async update(auth, id, dto)                  // Update asset properties
async updateAll(auth, dto)                   // Bulk update with geolocation sync
async deleteAll(auth, dto)                   // Trash or permanently delete
async editAsset(auth, id, dto)              // Apply edits (crop, rotate, trim)
async removeAssetEdits(auth, id)            // Undo all edits
async getMetadata(auth, id)                 // Get custom metadata
async upsertMetadata(auth, id, dto)         // Create/update metadata
```

#### 2. **SearchService**
**File**: [`server/src/services/search.service.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/services/search.service.ts)

**Responsibilities**:
- Metadata search (dates, locations, camera, etc.)
- Smart search (CLIP embeddings)
- Random asset selection
- Search suggestions (countries, cities, camera models)
- Filter suggestions

**Key Methods**:
```typescript
async searchMetadata(auth, dto)              // Find by EXIF, type, date, etc.
async searchSmart(auth, dto)                 // CLIP-based semantic search
async searchRandom(auth, dto)                // Random selection
async getSearchSuggestions(auth, dto)        // Autocomplete hints
async getFilterSuggestions(auth, dto)        // Available filters for current context
```

#### 3. **AlbumService**
**File**: `server/src/services/album.service.ts`

**Responsibilities**:
- Album CRUD operations
- Album sharing and access control
- Asset management within albums
- Album statistics

**Key Methods** (from controller):
```typescript
async getAll(auth, query)                    // List all albums
async get(auth, id)                          // Get single album
async create(auth, dto)                      // Create new album
async update(auth, id, dto)                  // Update album metadata
async delete(auth, id)                       // Delete album (soft then hard)
async addAssets(auth, id, dto)              // Add assets to album
async addAssetsToAlbums(auth, dto)          // Batch add to multiple albums
async removeAssets(auth, id, dto)           // Remove assets from album
async addUsers(auth, id, dto)                // Share with users
async updateUser(auth, id, userId, dto)     // Change user role
async removeUser(auth, id, userId)          // Unshare album
```

#### 4. **SharedSpaceService** (Fork-Specific)
**File**: `server/src/services/shared-space.service.ts`

**Responsibilities**:
- Shared space creation and management
- Member invitations and role management
- Per-space person aliases
- Activity logging
- Space-specific filtering

**Key Features**:
- Collaborative photo sharing across users
- Per-space person name customization
- Role-based access (Owner/Admin/Editor/Viewer)
- Upload/delete permissions per member

#### 5. **MachineLearningRepository**
**Purpose**: Communicate with Python ML service

**Endpoints Called**:
```
POST /ml/clip/text-encode          → Encode text to CLIP embedding
POST /ml/clip/image-encode         → Encode image to CLIP embedding
POST /ml/detect-faces              → Facial recognition
POST /ml/detect-objects            → Object detection (pets)
POST /ml/ocr                        → Text extraction
POST /ml/duplicate-detection       → Find duplicate videos
```

---

### Background Job System

**Job Queue**: BullMQ + Redis

**Job Types** (AssetJobName):

| Job | Trigger | Description |
|-----|---------|-------------|
| `AssetExtractMetadata` | Asset upload | Extract EXIF, GPS, dimensions |
| `AssetGenerateThumbnails` | Asset upload | Create thumbnail & preview |
| `AssetDetectFaces` | Asset upload (if ML enabled) | Facial recognition |
| `AssetGenerateClipEmbedding` | Asset upload (if ML enabled) | Generate CLIP embedding for smart search |
| `AssetEncodeVideo` | Asset upload + manual | Transcode video to playback format |
| `AssetDeleteCheck` | Periodic (maintenance) | Find trashed assets older than retention |
| `AssetDelete` | Triggered by check job | Permanently delete asset files |
| `AssetEditThumbnailGeneration` | Image/video edit | Regenerate thumbnail after edits |
| `DuplicateDetection` | Manual or scheduled | Find duplicate photos/videos |

**Job Handling Example** (from AssetService):

```typescript
@OnJob({ name: JobName.AssetDelete, queue: QueueName.BackgroundTask })
async handleAssetDeletion(job: JobOf<JobName.AssetDelete>): Promise<JobStatus> {
  // Delete files, update DB, emit events
}
```

---

## Fork-Specific Features

### 1. **Shared Spaces**
**Purpose**: Collaborative photo sharing (unlike albums which are one-way)

**Flow**:
```
Owner creates Space
    ↓
Owner invites members (Owner/Admin/Editor/Viewer roles)
    ↓
Members can upload photos to the space
    ↓
All members see and can manage space photos
    ↓
Per-member person aliases (e.g., "John" → "Dad" in Family Space)
```

**Tables**:
- `shared-space.table.ts`
- `shared-space-member.table.ts`
- `shared-space-asset.table.ts`
- `shared-space-person.table.ts`

---

### 2. **User Groups**
**Purpose**: Quick sharing with groups instead of selecting users individually

**Example**:
```
Create group "Family" (Alice, Bob, Charlie)
    ↓
Share album → select "Family" (quick one-click)
    ↓
All 3 members get album access
```

**Tables**:
- `user-group.table.ts`
- `user-group-member.table.ts`

---

### 3. **Image Editing & Video Trimming**
**Purpose**: Non-destructive in-app editing

**Supported Operations**:
- **Images**: Rotate, Mirror, Crop
- **Videos**: Trim (with frame precision)

**Flow**:
```
User makes edits
    ↓
Store edit instructions (not destructive)
    ↓
Regenerate thumbnails
    ↓
Original file untouched (can undo)
    ↓
Apply edits on-the-fly for thumbnail/preview
```

**Table**:
- `asset-edit.table.ts`

---

### 4. **Pet Detection** (YOLO-based)
**Purpose**: Automatically tag pets in photos

**Flow**:
```
Upload photo with dog
    ↓
ML Service: YOLO11 object detection
    ↓
Detect "dog" → tag as pet
    ↓
Appears in People section as "Pets"
    ↓
User can view all pet photos
```

---

### 5. **Auto-Classification**
**Purpose**: Automatically categorize and archive photos based on CLIP + text prompts

**Example**:
```
Admin defines category: "Screenshots"
    Prompt: "computer screen, screenshot, terminal"
    ↓
System scans all photos with CLIP
    ↓
High-matching screenshots auto-tagged
    ↓
User can auto-archive them
```

---

### 6. **Video Duplicate Detection**
**Purpose**: Extend upstream's photo dedup to videos

**Algorithm**:
```
Extract multiple frames from video
    ↓
Generate CLIP embedding for each frame
    ↓
Average embeddings into single vector
    ↓
Compare with other videos using vector similarity
    ↓
Identify duplicates
```

---

### 7. **Google Photos Import**
**Purpose**: Import entire Google Takeout archive

**Flow**:
```
User uploads Takeout zip
    ↓
Web UI: 5-step guided wizard
    ├─ Step 1: Select zip/folder
    ├─ Step 2: Scan and extract metadata
    ├─ Step 3: Choose which years/types to import
    ├─ Step 4: Map folder structure
    ├─ Step 5: Confirm and import
    ↓
Assets imported with original metadata
```

---

### 8. **S3-Compatible Storage**
**Purpose**: Store photos in AWS S3, MinIO, Backblaze, etc.

**Configuration** (via environment):
```bash
STORAGE_TYPE=s3
S3_BUCKET=my-bucket
S3_REGION=us-east-1
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
```

**Supported Backends**:
- AWS S3
- MinIO
- Cloudflare R2
- Backblaze B2
- Wasabi
- DigitalOcean Spaces

---

## Request/Response Flow Example: Upload & Search

### Complete Example: User uploads photo, then searches

```
┌─────────────────────────────────────────────────────────────┐
│                        STEP 1: UPLOAD                       │
└─────────────────────────────────────────────────────────────┘

User clicks "Upload"
    │
    ├─ POST /assets/upload
    │   Headers: { Authorization: Bearer <token> }
    │   Body: multipart/form-data (image file + metadata)
    │
    ▼
AssetController.uploadFile(auth, file, dto)
    │
    ├─ Validate file: size, type, MIME
    │
    ├─ Store file to disk/S3 using StorageCore
    │
    ├─ Create Asset record (id=uuid, ownerId, originalPath, etc.)
    │
    ├─ Queue jobs (via JobRepository):
    │   {
    │     name: JobName.AssetExtractMetadata,
    │     data: { id: assetId }
    │   },
    │   {
    │     name: JobName.AssetGenerateThumbnails,
    │     data: { id: assetId }
    │   },
    │   {
    │     name: JobName.AssetDetectFaces,
    │     data: { id: assetId }
    │   },
    │   {
    │     name: JobName.AssetGenerateClipEmbedding,
    │     data: { id: assetId }
    │   }
    │
    ▼
Response: AssetResponseDto
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ownerId": "user-1",
  "filename": "beach-sunset.jpg",
  "type": "Image",
  "fileSize": 2097152,
  "createdAt": "2024-04-22T12:00:00Z",
  "exifInfo": null,         // Will be populated after metadata extraction
  "status": "Active",
  "visibility": "Private"
}

Meanwhile, background workers process jobs...

┌─────────────────────────────────────────────────────────────┐
│               STEP 2: BACKGROUND PROCESSING                │
└─────────────────────────────────────────────────────────────┘

Job: AssetExtractMetadata
    │
    ├─ Read image file
    │
    ├─ Extract EXIF using exiftool
    │   {
    │     "DateTime": "2024-04-15T14:30:00Z",
    │     "GPS": "40.7128° N, 74.0060° W",
    │     "Make": "Canon",
    │     "Model": "EOS 5D Mark IV",
    │     "FocalLength": "50mm",
    │     "ISO": 100,
    │     "FNumber": 2.8
    │   }
    │
    ├─ Reverse geocode GPS → country/state/city
    │   GET /map/reverse-geocode?lat=40.7128&lng=-74.0060
    │   Response: {country: "USA", state: "NY", city: "New York"}
    │
    ├─ Store in asset_exif table
    │
    ▼
Job: AssetGenerateThumbnails
    │
    ├─ Create 250x250 thumbnail (JPEG)
    │
    ├─ Create 1920x1080 preview (JPEG)
    │
    ├─ Store paths as AssetFile records
    │
    ▼
Job: AssetDetectFaces
    │
    ├─ Load image
    │
    ├─ Call ML Service: POST /ml/detect-faces
    │   Response: [
    │     { x: 100, y: 150, width: 80, height: 100, embedding: [0.1, 0.2, ...], confidence: 0.95 }
    │   ]
    │
    ├─ For each detected face:
    │   ├─ Query FaceSearchRepository for similar faces
    │   ├─ Find best match person or create new
    │   ├─ Create AssetFace record with embedding
    │
    ▼
Job: AssetGenerateClipEmbedding
    │
    ├─ Call ML Service: POST /ml/clip/image-encode
    │   Body: { imagePath: "...", modelName: "clip-vit-base-patch32" }
    │
    ├─ ML Service:
    │   ├─ Load image
    │   ├─ Preprocess
    │   ├─ Run through CLIP image encoder (ViT)
    │   ├─ Return 1536-dimensional embedding
    │
    ├─ Store embedding in smart_search table
    │
    ▼
Asset ready for smart search!

┌─────────────────────────────────────────────────────────────┐
│                 STEP 3: SEARCH (days later)                │
└─────────────────────────────────────────────────────────────┘

User types: "beach sunset"
    │
    ├─ GET /search/smart?query=beach%20sunset&size=100
    │
    ▼
SearchService.searchSmart(auth, dto)
    │
    ├─ Check ML enabled: config.machineLearning.clip.enabled = true
    │
    ├─ Check embedding cache (LRUMap)
    │   key = "clip-vit-base-patch32" + "beach sunset" + "en"
    │   NOT IN CACHE
    │
    ├─ Call ML Service: POST /ml/clip/text-encode
    │   {
    │     "text": "beach sunset",
    │     "modelName": "clip-vit-base-patch32",
    │     "language": "en"
    │   }
    │
    │   ML Service:
    │   ├─ Tokenize text
    │   ├─ Run through CLIP text encoder (Transformer)
    │   ├─ Return 1536-dim embedding
    │
    │   Response: [0.15, -0.42, ..., 0.88]
    │
    ├─ Cache embedding (LRUMap, up to 100)
    │
    ├─ Query SearchRepository.searchSmart():
    │   SQL (simplified):
    │   SELECT asset, smart_search_embedding
    │   FROM assets
    │   JOIN smart_search ON assets.id = smart_search.assetId
    │   WHERE assets.ownerId = 'user-1'
    │   AND assets.visibility != 'Locked'
    │   AND assets.status = 'Active'
    │   -- Use pgvector similarity:
    │   ORDER BY smart_search_embedding <-> query_embedding ASC
    │   LIMIT 100
    │
    │   Returns: [
    │     { assetId: "550e8400-e29b-41d4-a716-446655440000", distance: 0.12 },
    │     { assetId: "...", distance: 0.23 },
    │     ...
    │   ]
    │
    ├─ Fetch full asset data for top results
    │
    ├─ Map to AssetResponseDto[]
    │   [
    │     {
    │       "id": "550e8400-e29b-41d4-a716-446655440000",
    │       "filename": "beach-sunset.jpg",
    │       "exifInfo": {
    │         "dateTimeOriginal": "2024-04-15T14:30:00Z",
    │         "country": "USA",
    │         "state": "NY",
    │         "city": "New York",
    │         "latitude": 40.7128,
    │         "longitude": -74.0060,
    │         "make": "Canon",
    │         "model": "EOS 5D Mark IV"
    │       },
    │       "faces": [
    │         {
    │           "id": "face-uuid",
    │           "personId": "person-uuid",
    │           "x": 100,
    │           "y": 150,
    │           "width": 80,
    │           "height": 100
    │         }
    │       ]
    │     }
    │   ]
    │
    ▼
Response sent to client

Client renders results
```

---

## Summary: Key Takeaways for New Developers

### Navigation Guide

**To understand a feature**, follow this pattern:

1. **Find the Controller** → `server/src/controllers/{feature}.controller.ts`
   - See HTTP endpoints, request/response DTOs
   - Example: [`album.controller.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/controllers/album.controller.ts)

2. **Find the Service** → `server/src/services/{feature}.service.ts`
   - Core business logic
   - Database access via injected repositories
   - Example: [`asset.service.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/services/asset.service.ts)

3. **Find the Repositories** → `server/src/repositories/{feature}.repository.ts`
   - Data access layer (Kysely ORM)
   - SQL query builders

4. **Find the Database Tables** → `server/src/schema/tables/{feature}.table.ts`
   - Column definitions, types, constraints
   - Example: [`asset.table.ts`](https://github.com/vinoduxdata/album/blob/main/server/src/schema/tables/asset.table.ts)

5. **Check the DTOs** → `server/src/dtos/{feature}.dto.ts`
   - Request/response shapes

### Dependency Injection

All services extend `BaseService` which injects ~40 repositories:

```typescript
export class AssetService extends BaseService {
  constructor(
    private assetRepository: AssetRepository,
    private albumRepository: AlbumRepository,
    private personRepository: PersonRepository,
    private searchRepository: SearchRepository,
    private jobRepository: JobRepository,
    // ... 35+ more repositories
  ) {
    super();
  }
}
```

### Authorization Pattern

```typescript
@Authenticated({ permission: Permission.AssetRead })
async get(auth: AuthDto, id: string) {
  // Auth guard checks user has permission
  await this.requireAccess({ 
    auth, 
    permission: Permission.AssetRead, 
    ids: [id] 
  });
}
```

### Database Transactions

Uses Kysely transaction support (see `database.ts` for transaction helpers).

### Testing

- **Unit tests**: Mock dependencies using `newTestService()` factory
- **Medium tests**: Require Docker database via testcontainers
- Run: `cd server && pnpm test`

---

## Additional Resources

- **Documentation**: https://docs.opennoodle.de
- **API Docs**: https://demo.opennoodle.de/doc (Swagger UI)
- **Roadmap**: https://opennoodle.de/roadmap
- **Contributing Guide**: [`CONTRIBUTING.md`](https://github.com/vinoduxdata/album/blob/main/CONTRIBUTING.md)
- **Dev Setup**: [`CLAUDE.md`](https://github.com/vinoduxdata/album/blob/main/CLAUDE.md)
