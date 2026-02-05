/*
 * CivetWeb HashLink Bindings
 * Native C bindings for CivetWeb to be used with HashLink
 */

#define HL_NAME(n) civetweb_##n
#include <hl.h>
#include "civetweb.h"
#include <string.h>
#include <stdio.h>

// Type definitions for HashLink
typedef struct {
    struct mg_context *ctx;
    struct mg_callbacks callbacks;
    char *document_root;
    int port;
    char *host;
    int running;
} hl_civetweb_server;

typedef struct {
    vbyte *uri;
    vbyte *method;
    vbyte *body;
    int body_length;
    vbyte *query_string;
    vbyte *remote_addr;
    vbyte *headers;
} hl_http_request;

typedef struct {
    int status_code;
    vbyte *content_type;
    vbyte *body;
    int body_length;
} hl_http_response;

// Global callback function pointer from Haxe (deprecated - kept for WebSocket compatibility)
static vclosure *g_request_handler = NULL;
static vclosure *g_websocket_connect_handler = NULL;
static vclosure *g_websocket_ready_handler = NULL;
static vclosure *g_websocket_data_handler = NULL;
static vclosure *g_websocket_close_handler = NULL;

// ============================================================================
// POLLING ARCHITECTURE: Request/Response Queue System
// ============================================================================

// Request queue entry
typedef struct queued_request {
    int request_id;
    struct mg_connection *conn;
    char uri[512];
    char method[16];
    char body[8192];
    int body_length;
    char query_string[512];
    char remote_addr[64];
    char headers[4096];
    struct queued_request *next;
} queued_request;

// Response queue entry
typedef struct queued_response {
    int request_id;
    int status_code;
    char content_type[128];
    char body[8192];
    int body_length;
    struct queued_response *next;
} queued_response;

// Thread-safe queues
static queued_request *g_request_queue_head = NULL;
static queued_request *g_request_queue_tail = NULL;
static queued_response *g_response_queue_head = NULL;
static queued_response *g_response_queue_tail = NULL;
static int g_next_request_id = 1;

// Mutexes for thread safety
#ifdef _WIN32
#include <windows.h>
static CRITICAL_SECTION g_request_mutex;
static CRITICAL_SECTION g_response_mutex;
static int g_mutexes_initialized = 0;

static void init_mutexes() {
    if (!g_mutexes_initialized) {
        InitializeCriticalSection(&g_request_mutex);
        InitializeCriticalSection(&g_response_mutex);
        g_mutexes_initialized = 1;
    }
}

static void lock_request_mutex() { EnterCriticalSection(&g_request_mutex); }
static void unlock_request_mutex() { LeaveCriticalSection(&g_request_mutex); }
static void lock_response_mutex() { EnterCriticalSection(&g_response_mutex); }
static void unlock_response_mutex() { LeaveCriticalSection(&g_response_mutex); }
#else
#include <pthread.h>
static pthread_mutex_t g_request_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_response_mutex = PTHREAD_MUTEX_INITIALIZER;

static void init_mutexes() {
    // Already initialized statically
}

static void lock_request_mutex() { pthread_mutex_lock(&g_request_mutex); }
static void unlock_request_mutex() { pthread_mutex_unlock(&g_request_mutex); }
static void lock_response_mutex() { pthread_mutex_lock(&g_response_mutex); }
static void unlock_response_mutex() { pthread_mutex_unlock(&g_response_mutex); }
#endif

// Helper: Wait for response with timeout (in milliseconds)
static queued_response* wait_for_response(int request_id, int timeout_ms) {
    int elapsed_ms = 0;
    int sleep_interval_ms = 10; // Check every 10ms
    
    while (elapsed_ms < timeout_ms) {
        lock_response_mutex();
        
        // Search for response
        queued_response *prev = NULL;
        queued_response *curr = g_response_queue_head;
        
        while (curr != NULL) {
            if (curr->request_id == request_id) {
                // Found it - remove from queue
                if (prev) {
                    prev->next = curr->next;
                } else {
                    g_response_queue_head = curr->next;
                }
                
                if (curr == g_response_queue_tail) {
                    g_response_queue_tail = prev;
                }
                
                unlock_response_mutex();
                return curr;
            }
            prev = curr;
            curr = curr->next;
        }
        
        unlock_response_mutex();
        
        // Sleep and retry
#ifdef _WIN32
        Sleep(sleep_interval_ms);
#else
        usleep(sleep_interval_ms * 1000);
#endif
        elapsed_ms += sleep_interval_ms;
    }
    
    return NULL; // Timeout
}


// WebSocket callback: connection established
static int websocket_connect_handler(const struct mg_connection *conn, void *user_data) {
    if (g_websocket_connect_handler != NULL) {
        // Call Haxe callback - return 0 to accept, non-zero to reject
        vdynamic *result = hl_dyn_call(g_websocket_connect_handler, NULL, 0);
        return result ? hl_dyn_geti(result, 0, &hlt_i32) : 0;
    }
    return 0; // Accept connection by default
}

// WebSocket callback: ready to communicate
static void websocket_ready_handler(struct mg_connection *conn, void *user_data) {
    if (g_websocket_ready_handler != NULL) {
        // Store connection pointer for later use
        vdynamic *conn_ptr = hl_alloc_dynamic(&hlt_bytes);
        hl_dyn_seti(conn_ptr, 0, &hlt_bytes, &conn);
        hl_dyn_call(g_websocket_ready_handler, conn_ptr, 1);
    }
}

// WebSocket callback: data received
static int websocket_data_handler(struct mg_connection *conn, int flags, char *data, size_t data_len, void *user_data) {
    if (g_websocket_data_handler != NULL) {
        // Prepare data for Haxe callback
        vdynamic *args[3];
        
        // Connection pointer
        args[0] = hl_alloc_dynamic(&hlt_bytes);
        hl_dyn_seti(args[0], 0, &hlt_bytes, &conn);
        
        // Flags (opcode: 1=text, 2=binary, 8=close, 9=ping, 10=pong)
        args[1] = hl_alloc_dynamic(&hlt_i32);
        hl_dyn_seti(args[1], 0, &hlt_i32, &flags);
        
        // Data
        args[2] = hl_alloc_dynamic(&hlt_bytes);
        vbyte *data_copy = (vbyte*)hl_gc_alloc_noptr(data_len + 1);
        memcpy(data_copy, data, data_len);
        data_copy[data_len] = '\0';
        hl_dyn_seti(args[2], 0, &hlt_bytes, &data_copy);
        
        vdynamic *result = hl_dyn_call(g_websocket_data_handler, args, 3);
        return result ? hl_dyn_geti(result, 0, &hlt_i32) : 1;
    }
    return 1; // Continue
}

// WebSocket callback: connection closed
static void websocket_close_handler(const struct mg_connection *conn, void *user_data) {
    if (g_websocket_close_handler != NULL) {
        vdynamic *conn_ptr = hl_alloc_dynamic(&hlt_bytes);
        hl_dyn_seti(conn_ptr, 0, &hlt_bytes, &conn);
        hl_dyn_call(g_websocket_close_handler, conn_ptr, 1);
    }
}

// Request handler callback that queues requests for Haxe polling
static int request_handler(struct mg_connection *conn, void *user_data) {
    const struct mg_request_info *request_info = mg_get_request_info(conn);
    
    // Allocate and populate request
    queued_request *req = (queued_request*)malloc(sizeof(queued_request));
    if (!req) {
        mg_printf(conn, "HTTP/1.1 500 Internal Server Error\r\n"
                       "Content-Type: text/plain\r\n"
                       "Content-Length: 21\r\n\r\n"
                       "Memory allocation error");
        return 1;
    }
    
    memset(req, 0, sizeof(queued_request));
    
    // Assign request ID
    lock_request_mutex();
    req->request_id = g_next_request_id++;
    unlock_request_mutex();
    
    req->conn = conn;
    
    // Copy request data (with bounds checking)
    if (request_info->request_uri) {
        strncpy(req->uri, request_info->request_uri, sizeof(req->uri) - 1);
    }
    if (request_info->request_method) {
        strncpy(req->method, request_info->request_method, sizeof(req->method) - 1);
    }
    if (request_info->query_string) {
        strncpy(req->query_string, request_info->query_string, sizeof(req->query_string) - 1);
    }
    if (request_info->remote_addr) {
        strncpy(req->remote_addr, request_info->remote_addr, sizeof(req->remote_addr) - 1);
    }
    
    // Collect headers
    int headers_offset = 0;
    for (int i = 0; i < request_info->num_headers && headers_offset < sizeof(req->headers) - 100; i++) {
        int written = snprintf(req->headers + headers_offset, 
                              sizeof(req->headers) - headers_offset,
                              "%s: %s\n",
                              request_info->http_headers[i].name,
                              request_info->http_headers[i].value);
        if (written > 0) {
            headers_offset += written;
        }
    }
    
    // Read request body if present
    int body_len = mg_read(conn, req->body, sizeof(req->body) - 1);
    if (body_len > 0) {
        req->body[body_len] = '\0';
        req->body_length = body_len;
    } else {
        req->body[0] = '\0';
        req->body_length = 0;
    }
    
    // Enqueue request
    lock_request_mutex();
    req->next = NULL;
    if (g_request_queue_tail) {
        g_request_queue_tail->next = req;
    } else {
        g_request_queue_head = req;
    }
    g_request_queue_tail = req;
    unlock_request_mutex();
    
    // Wait for response (30 second timeout)
    queued_response *resp = wait_for_response(req->request_id, 30000);
    
    if (resp) {
        // Send response
        mg_printf(conn, "HTTP/1.1 %d OK\r\n", resp->status_code);
        mg_printf(conn, "Content-Type: %s\r\n", resp->content_type);
        mg_printf(conn, "Content-Length: %d\r\n\r\n", resp->body_length);
        mg_write(conn, resp->body, resp->body_length);
        
        free(resp);
        free(req);
        return 1;
    }
    
    // Timeout - send 504
    mg_printf(conn, "HTTP/1.1 504 Gateway Timeout\r\n"
                   "Content-Type: text/plain\r\n"
                   "Content-Length: 37\r\n\r\n"
                   "Request processing timeout (30 seconds)");
    
    free(req);
    return 1;
}

// Create a new CivetWeb server instance
HL_PRIM hl_civetweb_server* HL_NAME(create)(vbyte *host, int port, vbyte *document_root) {
    hl_civetweb_server *server = (hl_civetweb_server*)malloc(sizeof(hl_civetweb_server));
    if (!server) return NULL;
    
    memset(server, 0, sizeof(hl_civetweb_server));
    server->port = port;
    server->host = strdup((char*)host);
    
    if (document_root) {
        server->document_root = strdup((char*)document_root);
    }
    
    server->running = 0;
    return server;
}

// Start the server
HL_PRIM bool HL_NAME(start)(hl_civetweb_server *server) {
    if (!server || server->running) return false;
    
    // Initialize mutexes for queue system
    init_mutexes();
    
    // Setup callbacks
    memset(&server->callbacks, 0, sizeof(server->callbacks));
    server->callbacks.begin_request = request_handler;
    
    // Build options array
    char port_str[32];
    snprintf(port_str, sizeof(port_str), "%d", server->port);
    
    const char *options[10];
    int opt_index = 0;
    
    options[opt_index++] = "listening_ports";
    options[opt_index++] = port_str;
    
    if (server->document_root) {
        options[opt_index++] = "document_root";
        options[opt_index++] = server->document_root;
    }
    
    options[opt_index++] = "num_threads";
    options[opt_index++] = "4";
    
    options[opt_index] = NULL;
    
    // Start CivetWeb
    server->ctx = mg_start(&server->callbacks, NULL, options);
    
    if (server->ctx) {
        // Register WebSocket handlers (Global handlers for all URIs)
        mg_set_websocket_handler(server->ctx, "/", websocket_connect_handler, websocket_ready_handler, websocket_data_handler, websocket_close_handler, NULL);
        
        server->running = 1;
        return true;
    }
    
    return false;
}

// Stop the server
HL_PRIM void HL_NAME(stop)(hl_civetweb_server *server) {
    if (!server || !server->running) return;
    
    if (server->ctx) {
        mg_stop(server->ctx);
        server->ctx = NULL;
    }
    
    server->running = 0;
}

// Check if server is running
HL_PRIM bool HL_NAME(is_running)(hl_civetweb_server *server) {
    return server && server->running;
}

// Get server port
HL_PRIM int HL_NAME(get_port)(hl_civetweb_server *server) {
    return server ? server->port : 0;
}

// Get server host
HL_PRIM vbyte* HL_NAME(get_host)(hl_civetweb_server *server) {
    return server && server->host ? (vbyte*)server->host : (vbyte*)"";
}

// Free server resources
HL_PRIM void HL_NAME(free)(hl_civetweb_server *server) {
    if (!server) return;
    
    if (server->running) {
        HL_NAME(stop)(server);
    }
    
    if (server->host) free(server->host);
    if (server->document_root) free(server->document_root);
    free(server);
}

// Set WebSocket handlers
HL_PRIM void HL_NAME(set_websocket_connect_handler)(vclosure *handler) {
    g_websocket_connect_handler = handler;
}

HL_PRIM void HL_NAME(set_websocket_ready_handler)(vclosure *handler) {
    g_websocket_ready_handler = handler;
}

HL_PRIM void HL_NAME(set_websocket_data_handler)(vclosure *handler) {
    g_websocket_data_handler = handler;
}

HL_PRIM void HL_NAME(set_websocket_close_handler)(vclosure *handler) {
    g_websocket_close_handler = handler;
}

// WebSocket send data
HL_PRIM int HL_NAME(websocket_send)(struct mg_connection *conn, int opcode, vbyte *data, int data_len) {
    if (!conn || !data) return -1;
    return mg_websocket_write(conn, opcode, (const char*)data, data_len);
}

// WebSocket close connection
HL_PRIM void HL_NAME(websocket_close)(struct mg_connection *conn, int code, vbyte *reason) {
    if (!conn) return;
    
    // Send close frame with code and reason
    char close_data[128];
    int close_len = 0;
    
    // Add 2-byte code
    close_data[0] = (code >> 8) & 0xFF;
    close_data[1] = code & 0xFF;
    close_len = 2;
    
    // Add reason if provided
    if (reason) {
        int reason_len = strlen((const char*)reason);
        if (reason_len > 125) reason_len = 125;
        memcpy(close_data + 2, reason, reason_len);
        close_len += reason_len;
    }
    
    mg_websocket_write(conn, 0x8, close_data, close_len);  // 0x8 = close frame
}

// ============================================================================
// POLLING ARCHITECTURE: Native Functions for Haxe
// ============================================================================

// Poll for pending requests (called from Haxe main thread)
HL_PRIM varray* HL_NAME(poll_requests)(hl_civetweb_server *server) {
    if (!server) return NULL;
    
    lock_request_mutex();
    
    // Count requests
    int count = 0;
    queued_request *curr = g_request_queue_head;
    while (curr) {
        count++;
        curr = curr->next;
    }
    
    if (count == 0) {
        unlock_request_mutex();
        return hl_alloc_array(&hlt_dyn, 0);
    }
    
    // Create array
    varray *arr = hl_alloc_array(&hlt_dyn, count);
    
    // Dequeue all requests
    curr = g_request_queue_head;
    int index = 0;
    
    while (curr) {
        // Create dynamic object for this request
        vdynamic *obj = hl_alloc_dynamic(&hlt_dyn);
        
        // Set fields
        hl_dyn_setp(obj, hl_hash_utf8("id"), &hlt_i32, &curr->request_id);
        hl_dyn_setp(obj, hl_hash_utf8("uri"), &hlt_bytes, &curr->uri);
        hl_dyn_setp(obj, hl_hash_utf8("method"), &hlt_bytes, &curr->method);
        hl_dyn_setp(obj, hl_hash_utf8("body"), &hlt_bytes, &curr->body);
        hl_dyn_setp(obj, hl_hash_utf8("bodyLength"), &hlt_i32, &curr->body_length);
        hl_dyn_setp(obj, hl_hash_utf8("queryString"), &hlt_bytes, &curr->query_string);
        hl_dyn_setp(obj, hl_hash_utf8("remoteAddr"), &hlt_bytes, &curr->remote_addr);
        hl_dyn_setp(obj, hl_hash_utf8("headers"), &hlt_bytes, &curr->headers);
        
        hl_aptr(arr, vdynamic*)[index++] = obj;
        curr = curr->next;
    }
    
    // Clear the queue (requests are now being processed)
    g_request_queue_head = NULL;
    g_request_queue_tail = NULL;
    
    unlock_request_mutex();
    
    return arr;
}

// Push a response for a request ID (called from Haxe main thread)
HL_PRIM void HL_NAME(push_response)(hl_civetweb_server *server, int request_id, int status_code, vbyte *content_type, vbyte *body, int body_length) {
    if (!server) return;
    
    // Allocate response
    queued_response *resp = (queued_response*)malloc(sizeof(queued_response));
    if (!resp) return;
    
    memset(resp, 0, sizeof(queued_response));
    resp->request_id = request_id;
    resp->status_code = status_code;
    resp->body_length = body_length;
    
    // Copy data with bounds checking
    if (content_type) {
        strncpy(resp->content_type, (const char*)content_type, sizeof(resp->content_type) - 1);
    } else {
        strncpy(resp->content_type, "text/html; charset=utf-8", sizeof(resp->content_type) - 1);
    }
    
    if (body && body_length > 0) {
        int copy_len = body_length < sizeof(resp->body) ? body_length : sizeof(resp->body) - 1;
        memcpy(resp->body, body, copy_len);
        resp->body_length = copy_len;
    }
    
    // Enqueue response
    lock_response_mutex();
    resp->next = NULL;
    if (g_response_queue_tail) {
        g_response_queue_tail->next = resp;
    } else {
        g_response_queue_head = resp;
    }
    g_response_queue_tail = resp;
    unlock_response_mutex();
}


// Define HashLink bindings
DEFINE_PRIM(_ABSTRACT(hl_civetweb_server), create, _BYTES _I32 _BYTES);
DEFINE_PRIM(_BOOL, start, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_VOID, stop, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_BOOL, is_running, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_I32, get_port, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_BYTES, get_host, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_VOID, free, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_VOID, set_websocket_connect_handler, _FUN(_VOID, _I32));
DEFINE_PRIM(_VOID, set_websocket_ready_handler, _FUN(_VOID, _DYN));
DEFINE_PRIM(_VOID, set_websocket_data_handler, _FUN(_VOID, _DYN _I32 _BYTES _I32));
DEFINE_PRIM(_VOID, set_websocket_close_handler, _FUN(_VOID, _DYN));
DEFINE_PRIM(_I32, websocket_send, _DYN _I32 _BYTES _I32);
DEFINE_PRIM(_VOID, websocket_close, _DYN _I32 _BYTES);
DEFINE_PRIM(_ARR, poll_requests, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_VOID, push_response, _ABSTRACT(hl_civetweb_server) _I32 _I32 _BYTES _BYTES _I32);

