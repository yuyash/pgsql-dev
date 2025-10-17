# PostgreSQL Docker Replication Environment

A Docker-based development environment for building PostgreSQL from source and testing logical replication between two independent PostgreSQL instances.

## Prerequisites

- **Docker**: Version 20.10 or higher
  - Install from [docker.com](https://docs.docker.com/get-docker/)
  - Verify installation: `docker --version`

- **Docker Compose**: Version 2.0 or higher
  - Included with Docker Desktop
  - Verify installation: `docker compose version`

- **System Requirements**:
  - At least 4GB of available RAM
  - 10GB of free disk space for build artifacts and data
  - Ports 5432 and 5433 available on the host

## Project Structure

```
.
├── Dockerfile                    # Multi-stage build for PostgreSQL
├── docker-compose.yml            # Orchestrates primary and replica nodes
├── docker-entrypoint.sh          # Container initialization script
├── config/
│   ├── primary/                  # Primary node configuration
│   │   ├── postgresql.conf
│   │   └── pg_hba.conf
│   └── replica/                  # Replica node configuration
│       ├── postgresql.conf
│       └── pg_hba.conf
├── data/
│   ├── primary/                  # Primary node data (created at runtime)
│   └── replica/                  # Replica node data (created at runtime)
└── postgresql/                   # PostgreSQL source code
```

## Getting Started

### Clone the PostgreSQL Repository

Before building, you need to clone the PostgreSQL source code into the `postgresql/` directory:

```bash
git clone https://git.postgresql.org/git/postgresql.git
```

## Build Instructions

### 1. Build the Docker Image

Build the PostgreSQL Docker image from source:

```bash
docker compose build
```

This process will:
- Install all build dependencies
- Compile PostgreSQL from the `/postgresql` directory
- Create a runtime image with the compiled binaries

**Note**: The initial build may take 10-20 minutes depending on your system.

### 2. Verify the Build

Check that the image was created successfully:

```bash
docker images | grep postgres
```

## Startup Instructions

### Start Both PostgreSQL Instances

```bash
docker compose up -d
```

This command starts:
- **postgres-primary**: Accessible on port 5432
- **postgres-replica**: Accessible on port 5433

### Verify Containers Are Running

```bash
docker compose ps
```

Both containers should show status as "Up".

### View Logs

Monitor the primary node:
```bash
docker compose logs -f postgres-primary
```

Monitor the replica node:
```bash
docker compose logs -f postgres-replica
```

### Stop the Environment

```bash
docker compose down
```

To remove data volumes as well:
```bash
docker compose down
rm -rf data/primary/* data/replica/*
```

## Connecting to PostgreSQL Instances

### Connect to Primary Node

Using `psql` from the host (requires PostgreSQL client):
```bash
psql -h localhost -p 5432 -U postgres
```

Using Docker exec:
```bash
docker compose exec postgres-primary psql -U postgres
```

### Connect to Replica Node

Using `psql` from the host:
```bash
psql -h localhost -p 5433 -U postgres
```

Using Docker exec:
```bash
docker compose exec postgres-replica psql -U postgres
```

### Default Credentials

- **Username**: `postgres`
- **Password**: `postgres` (configured in docker-compose.yml)

## Setting Up Logical Replication

### Step 1: Create a Test Database and Table on Primary

```bash
docker compose exec postgres-primary psql -U postgres
```

```sql
-- Create a test database
CREATE DATABASE testdb;
\c testdb

-- Create a test table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some test data
INSERT INTO users (name, email) VALUES 
    ('Alice', 'alice@example.com'),
    ('Bob', 'bob@example.com');
```

### Step 2: Create a Publication on Primary

```sql
-- Create a publication for the users table
CREATE PUBLICATION users_pub FOR TABLE users;

-- Verify the publication
SELECT * FROM pg_publication;
```

### Step 3: Create the Same Database and Table on Replica

```bash
docker compose exec postgres-replica psql -U postgres
```

```sql
-- Create the same database
CREATE DATABASE testdb;
\c testdb

-- Create the same table structure (no data needed)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Step 4: Create a Subscription on Replica

```sql
-- Create a subscription to the primary's publication
CREATE SUBSCRIPTION users_sub
    CONNECTION 'host=postgres-primary port=5432 dbname=testdb user=postgres password=postgres'
    PUBLICATION users_pub;

-- Verify the subscription
SELECT * FROM pg_subscription;
```

### Step 5: Verify Replication

On the replica, check that data was replicated:

```sql
SELECT * FROM users;
```

You should see the two users inserted on the primary.

### Step 6: Test Real-Time Replication

On the primary, insert more data:

```sql
\c testdb
INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com');
```

On the replica, verify the new data appears:

```sql
\c testdb
SELECT * FROM users;
```

### Monitor Replication Status

On the primary, check replication slots:

```sql
SELECT * FROM pg_replication_slots;
```

On the replica, check subscription status:

```sql
SELECT * FROM pg_stat_subscription;
```

## Cheat Commands

### Issue: Containers Fail to Start

**Symptoms**: `docker compose up` fails or containers exit immediately

**Solutions**:
1. Check if ports 5432 or 5433 are already in use:
   ```bash
   lsof -i :5432
   lsof -i :5433
   ```
   
2. View container logs for errors:
   ```bash
   docker compose logs postgres-primary
   docker compose logs postgres-replica
   ```

3. Ensure data directories have correct permissions:
   ```bash
   sudo chown -R 999:999 data/primary data/replica
   ```

### Issue: Cannot Connect to PostgreSQL

**Symptoms**: Connection refused or timeout errors

**Solutions**:
1. Verify containers are running:
   ```bash
   docker compose ps
   ```

2. Check PostgreSQL is listening:
   ```bash
   docker compose exec postgres-primary pg_isready -U postgres
   ```

3. Verify network connectivity:
   ```bash
   docker compose exec postgres-primary ping postgres-replica
   ```

4. Check `pg_hba.conf` allows connections from your IP

### Issue: Replication Not Working

**Symptoms**: Data doesn't appear on replica, subscription shows errors

**Solutions**:
1. Verify `wal_level` is set to `logical` on both nodes:
   ```sql
   SHOW wal_level;
   ```

2. Check replication slots on primary:
   ```sql
   SELECT * FROM pg_replication_slots;
   ```

3. Verify subscription status on replica:
   ```sql
   SELECT subname, subenabled, subslotname FROM pg_subscription;
   SELECT * FROM pg_stat_subscription;
   ```

4. Check for errors in subscription worker logs:
   ```bash
   docker compose logs postgres-replica | grep -i error
   ```

5. Ensure the table structure is identical on both nodes

### Issue: Build Fails

**Symptoms**: `docker compose build` fails with compilation errors

**Solutions**:
1. Ensure the `/postgresql` directory contains valid source code:
   ```bash
   ls -la postgresql/
   ```

2. Check if `configure` script exists:
   ```bash
   ls postgresql/configure
   ```

3. Clean build cache and retry:
   ```bash
   docker compose build --no-cache
   ```

4. Check Docker has enough resources (memory, disk space)

### Issue: Permission Denied Errors

**Symptoms**: PostgreSQL fails to write to data directory

**Solutions**:
1. The postgres user in the container runs as UID 999. Fix permissions:
   ```bash
   sudo chown -R 999:999 data/
   ```

2. Ensure data directories exist:
   ```bash
   mkdir -p data/primary data/replica
   ```

### Issue: Out of Disk Space

**Symptoms**: Build fails or containers crash with disk space errors

**Solutions**:
1. Clean up Docker resources:
   ```bash
   docker system prune -a
   ```

2. Remove old PostgreSQL data:
   ```bash
   rm -rf data/primary/* data/replica/*
   ```

3. Check available disk space:
   ```bash
   df -h
   ```

## Configuration

### Modifying PostgreSQL Settings

Configuration files are located in `config/primary/` and `config/replica/`:

1. Edit the desired configuration file:
   ```bash
   vim config/primary/postgresql.conf
   ```

2. Restart the container to apply changes:
   ```bash
   docker compose restart postgres-primary
   ```

### Key Configuration Parameters

**For Logical Replication** (already configured):
- `wal_level = logical`
- `max_replication_slots = 4`
- `max_wal_senders = 4`
- `listen_addresses = '*'`

**For Performance Tuning**:
- `shared_buffers`: Amount of memory for caching
- `work_mem`: Memory for query operations
- `maintenance_work_mem`: Memory for maintenance operations

### Changing the Password

Edit `docker-compose.yml` and modify the `POSTGRES_PASSWORD` environment variable, then recreate the containers:

```bash
docker compose down -v
docker compose up -d
```

## Advanced Usage

### Accessing PostgreSQL Binaries

Run PostgreSQL commands directly:

```bash
docker compose exec postgres-primary pg_config
docker compose exec postgres-primary postgres --version
```

### Debugging

Enable query logging by adding to `postgresql.conf`:

```
log_statement = 'all'
log_duration = on
```

Then restart and view logs:

```bash
docker compose restart postgres-primary
docker compose logs -f postgres-primary
```

### Backup and Restore

Create a backup:

```bash
docker compose exec postgres-primary pg_dump -U postgres testdb > backup.sql
```

Restore a backup:

```bash
cat backup.sql | docker compose exec -T postgres-replica psql -U postgres testdb
```

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Logical Replication Guide](https://www.postgresql.org/docs/current/logical-replication.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## License

This project uses PostgreSQL source code, which is licensed under the PostgreSQL License. See the `postgresql/COPYRIGHT` file for details.
