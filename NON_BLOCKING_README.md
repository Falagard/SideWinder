# SideWinder: Non-Blocking Architecture Roadmap

The current implementation provides a robust "Dispatcher Pattern" to offload long-running tasks from SideWinder's main 60fps loop. Below are the proposed architectural improvements for future development.

## 1. Adaptive Event Loop (Headless Mode)
**Current State**: The server runs at a fixed 16ms pulse (60fps) regardless of load.
**Improvement**: When running as a pure web server (without a UI), the pulse should be adaptive. 
- Use OS-level notification (like `kqueue` or `epoll` via native bindings) to "wake up" the server only when data is actually waiting in the queue.
- **Benefit**: Significantly reduced idle CPU usage.

## 2. Shared-State Worker Islands
**Current State**: Logic is strictly single-threaded on the Main Thread.
**Improvement**: Implement an **Island Architecture**.
- Spin up multiple "Logic Threads" (Islands).
- Partition the incoming requests (e.g., by Session ID or Route) so that different threads handle different requests.
- **Benefit**: True multi-core utilization for logic, not just for networking.

## 3. Persistent Backing for Core Services
**Current State**: `JobStore`, `LocalStreamBroker`, and `InMemoryCacheService` are all in-memory.
**Improvement**: Create production-ready implementations:
- **`SqliteStreamBroker`**: Store stream messages in a database so they survive a server crash.
- **`RedisAdapter`**: Allow SideWinder to use Redis as the backend for streams and messaging, enabling horizontal scaling (multiple SideWinder instances sharing one task queue).

## 4. Advanced "Promise-like" Handling (Async/Await Simulation)
**Current State**: Handlers are synchronous. Async work requires manual job dispatching.
**Improvement**: Build a macro-based system or a specialized `AsyncHandler` that allows for a more natural syntax:
```haxe
App.asyncGet("/data", async (req, res) -> {
    var data = await fetchExternalData(); // This pauses the handler, but NOT the main loop
    res.write(data);
});
```
- This would use Fiber-like tech or a state-machine transform to yield control back to the game loop while waiting.

## 5. Formalized Middleware Pipeline
**Current State**: Middleware is supported but relies on simple closures.
**Improvement**: Implement a robust request context and a "next()" chain that supports pre-processing, post-processing, and error recovery.

---

> [!TIP]
> **Priority Item**: Moving the `JobStore` to a SQLite backend (Proposal #3) is the most impactful next step to make the system resilient to server restarts.
