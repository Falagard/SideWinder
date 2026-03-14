# SideWinder System Architecture

This document provides a high-level overview of the SideWinder system architecture, captured to assist with future development and maintenance.

## Core Philosophical Principles
- **Separation of Concerns**: Logic is divided into distinct layers (Interfaces, Services, Controllers, Adapters).
- **Dependency Injection**: Services are registered and resolved via a central DI container (`sidewinder.core.DI`).
- **Annotation-Driven Routing**: Routes and permissions are defined using metadata on interfaces (e.g., `@get`, `@requiresPermission`).

---

## System Layers

### 1. Interface Layer (`sidewinder.interfaces`)
Defines the "contracts" for all services. This allows for mock implementations during testing and decoupled communication.
- **`IUserServiceHandler`**: REST-style endpoints for user management.
- **`IAuthService`**: Authentication logic (OAuth, Magic Links, API Keys).
- **`IDatabaseService`**: Abstract database operations.

### 2. Service Layer (`sidewinder.services`)
Concrete implementations of the interfaces.
- **`UserService`**: Handles user persistence and lookups.
- **`AuthService`**: Manages sessions, token generation, and provider-specific authentication flows.
- **`SqliteDatabaseService`**: Optimized SQLite implementation using a background writer thread for serialized writes and WAL mode for concurrent reads.

### 3. Middleware Layer (`sidewinder.middleware`)
Interceptors for the request/response pipeline.
- **`AuthMiddleware`**: Extracts credentials from headers (`Authorization`, `X-API-KEY`) or cookies (`auth_token`) and populates the `AuthContext` on the request.

### 4. Routing & Web Layer (`sidewinder.routing`, `sidewinder.adapters`)
- **`Router`**: The core multiplexer for HTTP requests.
- **`AutoRouter`**: A macro-based tool that automatically registers routes by inspecting interface metadata.
- **`HxWellAdapter` / `CivetWebAdapter`**: Adapters that bridge the Haxe logic to specific low-level web server implementations.

---

## Database Schema Highlights
- **`users`**: Core user data and stringified JSON permissions.
- **`user_api_keys`**: Stores API key hashes associated with users, with an `is_active` flag for revocation.
- **`migrations`**: Tracks versioned SQL files applied to the database.

---

## Background Tasks
- **`GenericJobWorker`**: Listens to a message stream (Redis-style streams via `IStreamBroker`) and processes background jobs (e.g., email notifications).

## Extension Points
- **OAuth Providers**: New providers can be registered in `AuthService` by implementing `IOAuthService`.
- **Logic Islands**: High-concurrency tasks can be distributed across "islands" managed by `IslandManager`.
