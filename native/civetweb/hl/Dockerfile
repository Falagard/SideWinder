FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for building HashLink and CivetWeb
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    libpng-dev \
    libturbojpeg-dev \
    libvorbis-dev \
    libopenal-dev \
    libsdl2-dev \
    libmbedtls-dev \
    libuv1-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Build HashLink from source
WORKDIR /tmp
RUN git clone https://github.com/HaxeFoundation/hashlink.git
WORKDIR /tmp/hashlink
# Checkout a recent stable version or stick to master if generally stable. 
# Using 1.14 tag for stability if possible, but master is often required for latest fix. 
# Let's stick to master for now as it's often more compatible with recent libraries.
RUN make && make install
RUN ldconfig

# Set HashLink environment variables
ENV HASHLINK_PATH=/usr/local

# Set up build directory
WORKDIR /app

# Copy CivetWeb source
# We expect the docker build context to be native/civetweb
COPY civetweb.c .
COPY civetweb.h .
COPY *.inl .
# Copy HL specific files
COPY hl/ hl/

# Run the build
WORKDIR /app/hl
RUN chmod +x build_hdll.sh
RUN sed -i 's/\r$//' build_hdll.sh
RUN ./build_hdll.sh
