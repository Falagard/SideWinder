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
} hl_http_request;

typedef struct {
    int status_code;
    vbyte *content_type;
    vbyte *body;
    int body_length;
} hl_http_response;

// Global callback function pointer from Haxe
static vclosure *g_request_handler = NULL;
static vclosure *g_websocket_connect_handler = NULL;
static vclosure *g_websocket_ready_handler = NULL;
static vclosure *g_websocket_data_handler = NULL;
static vclosure *g_websocket_close_handler = NULL;

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
        
        vdynamic *result = hl_dyn_calln(g_websocket_data_handler, args, 3);
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

// Request handler callback that bridges CivetWeb to Haxe
static int request_handler(struct mg_connection *conn, void *user_data) {
    if (g_request_handler == NULL) {
        mg_printf(conn, "HTTP/1.1 500 Internal Server Error\r\n"
                       "Content-Type: text/plain\r\n"
                       "Content-Length: 28\r\n\r\n"
                       "No request handler configured");
        return 1;
    }

    const struct mg_request_info *request_info = mg_get_request_info(conn);
    
    // Prepare request data for Haxe
    hl_http_request req;
    req.uri = (vbyte*)request_info->request_uri;
    req.method = (vbyte*)request_info->request_method;
    req.query_string = (vbyte*)request_info->query_string;
    req.remote_addr = (vbyte*)request_info->remote_addr;
    
    // Read request body if present
    char body_buffer[8192];
    int body_len = mg_read(conn, body_buffer, sizeof(body_buffer) - 1);
    if (body_len > 0) {
        body_buffer[body_len] = '\0';
        req.body = (vbyte*)body_buffer;
        req.body_length = body_len;
    } else {
        req.body = (vbyte*)"";
        req.body_length = 0;
    }

    // Call Haxe callback
    vdynamic *result = hl_dyn_call(g_request_handler, &req, 1);
    
    if (result == NULL) {
        mg_printf(conn, "HTTP/1.1 500 Internal Server Error\r\n"
                       "Content-Type: text/plain\r\n"
                       "Content-Length: 21\r\n\r\n"
                       "Handler returned null");
        return 1;
    }

    // Extract response data
    hl_http_response *resp = (hl_http_response*)result;
    
    // Send response
    mg_printf(conn, "HTTP/1.1 %d OK\r\n", resp->status_code);
    mg_printf(conn, "Content-Type: %s\r\n", resp->content_type ? (char*)resp->content_type : "text/html");
    mg_printf(conn, "Content-Length: %d\r\n\r\n", resp->body_length);
    mg_write(conn, resp->body, resp->body_length);
    
    return 1; // Mark as processed
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
HL_PRIM bool HL_NAME(start)(hl_civetweb_server *server, vclosure *handler) {
    if (!server || server->running) return false;
    
    g_request_handler = handler;
    
    // Setup callbacks
    memset(&server->callbacks, 0, sizeof(server->callbacks));
    server->callbacks.begin_request = request_handler;
    
    // Setup WebSocket callbacks
    server->callbacks.websocket_connect = websocket_connect_handler;
    server->callbacks.websocket_ready = websocket_ready_handler;
    server->callbacks.websocket_data = websocket_data_handler;
    
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

// Define HashLink bindings
DEFINE_PRIM(_ABSTRACT(hl_civetweb_server), create, _BYTES _I32 _BYTES);
DEFINE_PRIM(_BOOL, start, _ABSTRACT(hl_civetweb_server) _FUN(_VOID, _DYN));
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
