# Multi-stage Dockerfile for PostgreSQL compilation from source

# Builder stage - compile PostgreSQL
FROM ubuntu:latest AS builder

# Install build prerequisites
RUN apt-get update && apt-get install -y \
    gcc \
    make \
    autoconf \
    automake \
    libtool \
    bison \
    flex \
    libreadline-dev \
    zlib1g-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev \
    libicu-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy PostgreSQL source code
COPY postgresql /usr/src/postgresql

# Set working directory
WORKDIR /usr/src/postgresql

# Configure PostgreSQL with appropriate flags
RUN ./configure \
    --prefix=/usr/local/pgsql \
    --with-openssl \
    --with-readline \
    --with-libxml \
    --with-libxslt \
    --with-icu \
    --enable-depend \
    --enable-debug \
    --enable-cassert \
    --enable-tap-tests \
    CFLAGS=-O0

# Compile PostgreSQL
RUN make -j$(nproc)

# Install PostgreSQL
RUN make install

# Runtime stage - minimal image with compiled PostgreSQL
FROM ubuntu:latest

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libreadline8 \
    zlib1g \
    libssl3 \
    libxml2 \
    libxslt1.1 \
    libicu72 \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Set environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PATH=/usr/local/pgsql/bin:$PATH \
    PGDATA=/var/lib/postgresql/data

# Copy compiled PostgreSQL from builder stage
COPY --from=builder /usr/local/pgsql /usr/local/pgsql

# Create postgres system user and required directories
RUN groupadd -r postgres --gid=999 && \
    useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres && \
    mkdir -p /var/lib/postgresql/data && \
    mkdir -p /var/run/postgresql && \
    mkdir -p /etc/postgresql

# Set appropriate file permissions for PostgreSQL directories
RUN chown -R postgres:postgres /var/lib/postgresql && \
    chown -R postgres:postgres /var/run/postgresql && \
    chown -R postgres:postgres /etc/postgresql && \
    chmod 700 /var/lib/postgresql/data

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Switch to postgres user
USER postgres

# Expose PostgreSQL port
EXPOSE 5432

# Set entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]

# Default command
CMD ["postgres"]
