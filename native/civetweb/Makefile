# Makefile for CivetWeb HashLink bindings

# Detect OS
UNAME_S := $(shell uname -s)

# Compiler and flags
CC = gcc
CFLAGS = -O2 -fPIC -std=c99 -Wall

# HashLink paths (adjust as needed)
HL_INCLUDE = /usr/local/include
HL_LIB = /usr/local/lib

# Output
OUTPUT = civetweb.hdll

# Source files
SOURCES = civetweb_hl.c civetweb.c
OBJECTS = $(SOURCES:.c=.o)

# Platform-specific settings
ifeq ($(UNAME_S),Linux)
    LDFLAGS = -shared -lpthread -ldl
    HL_INCLUDE = /usr/include/hl
endif
ifeq ($(UNAME_S),Darwin)
    LDFLAGS = -dynamiclib -lpthread
    HL_INCLUDE = /usr/local/include
endif
ifeq ($(OS),Windows_NT)
    OUTPUT = civetweb.hdll
    LDFLAGS = -shared -lws2_32
    HL_INCLUDE = C:/HaxeToolkit/hl/include
endif

# Targets
all: download_civetweb $(OUTPUT)

download_civetweb:
	@if [ ! -f civetweb.c ]; then \
		echo "Downloading CivetWeb..."; \
		curl -L -o civetweb.c https://raw.githubusercontent.com/civetweb/civetweb/master/src/civetweb.c; \
		curl -L -o civetweb.h https://raw.githubusercontent.com/civetweb/civetweb/master/include/civetweb.h; \
	fi

$(OUTPUT): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -I$(HL_INCLUDE) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(OUTPUT)

distclean: clean
	rm -f civetweb.c civetweb.h

install: $(OUTPUT)
	@mkdir -p ../../Export/hl/bin
	cp $(OUTPUT) ../../Export/hl/bin/

.PHONY: all clean distclean install download_civetweb
