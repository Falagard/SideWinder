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

// Define HashLink bindings
DEFINE_PRIM(_ABSTRACT(hl_civetweb_server), create, _BYTES _I32 _BYTES);
DEFINE_PRIM(_BOOL, start, _ABSTRACT(hl_civetweb_server) _FUN(_VOID, _DYN));
DEFINE_PRIM(_VOID, stop, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_BOOL, is_running, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_I32, get_port, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_BYTES, get_host, _ABSTRACT(hl_civetweb_server));
DEFINE_PRIM(_VOID, free, _ABSTRACT(hl_civetweb_server));
