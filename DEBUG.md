# Debugging PostgreSQL with GDB in VS Code

This guide explains how to debug PostgreSQL running in Docker containers using GDB and VS Code.

## Prerequisites

- VS Code with the **C/C++ Extension** (ms-vscode.cpptools) installed
- Docker and Docker Compose running
- PostgreSQL containers built and running
- PostgreSQL source code in the `postgresql/` directory

## Quick Start

1. Start the PostgreSQL containers:
   ```bash
   docker compose up -d
   ```

2. Open VS Code in this workspace
3. Go to the Debug panel (Cmd+Shift+D or Ctrl+Shift+D)
4. Select a debug configuration from the dropdown
5. Press F5 to start debugging

## Debug Configurations

### 1. Debug PostgreSQL Primary (Docker)

Attaches to the main PostgreSQL postmaster process on the primary node.

**When to use**: Debugging server startup, configuration loading, or postmaster-level code.

**Steps**:
1. Select "Debug PostgreSQL Primary (Docker)" from the debug dropdown
2. Press F5
3. VS Code will show a process picker - select the `postgres` process (usually the one with the lowest PID)
4. Set breakpoints in your source code
5. Trigger the code path you want to debug

### 2. Debug PostgreSQL Replica (Docker)

Attaches to the main PostgreSQL postmaster process on the replica node.

**When to use**: Debugging replication-specific code, WAL receiver, or replica-side logic.

**Steps**: Same as Primary, but targets the replica container.

### 3. Debug PostgreSQL Backend Process

Attaches to a specific backend process handling a client connection.

**When to use**: Debugging query execution, transaction handling, or client-specific code paths.

**Steps**:
1. Connect to PostgreSQL and identify the backend PID:
   ```bash
   docker compose exec postgres-primary psql -U postgres -c "SELECT pg_backend_pid();"
   ```
   
2. Select "Debug PostgreSQL Backend Process" from the debug dropdown
3. Press F5
4. Enter the PID when prompted
5. Set breakpoints and execute queries to trigger them

## Configuration Details

### Docker Compose Settings

The containers are configured with debugging capabilities:

```yaml
cap_add:
  - SYS_PTRACE          # Allows ptrace system calls for debugging
security_opt:
  - seccomp:unconfined  # Disables seccomp filtering for debugging
volumes:
  - ./postgresql:/usr/src/postgresql:ro  # Source code mapping
```

### VS Code Launch Configuration

Located in `.vscode/launch.json`, the configurations use:

- **pipeTransport**: Runs gdb inside the Docker container
- **sourceFileMap**: Maps container paths to local source code
- **processId**: Allows attaching to running processes

### VS Code C/C++ Settings

Located in `.vscode/settings.json`:

- **includePath**: Points to PostgreSQL headers for IntelliSense
- **compilerPath**: Specifies the compiler for code analysis
- **intelliSenseMode**: Configured for ARM64 Linux (adjust if needed)

## Common Debugging Workflows

### Debugging Query Execution

1. Start PostgreSQL and connect:
   ```bash
   docker compose up -d
   docker compose exec postgres-primary psql -U postgres
   ```

2. Get the backend PID:
   ```sql
   SELECT pg_backend_pid();
   ```

3. In VS Code, set breakpoints in query execution code:
   - `src/backend/executor/execMain.c` - Query executor entry point
   - `src/backend/optimizer/plan/planner.c` - Query planner
   - `src/backend/parser/parse_analyze.c` - Query parser

4. Attach debugger to the backend PID

5. Execute a query in psql:
   ```sql
   SELECT * FROM pg_class LIMIT 1;
   ```

6. The debugger will hit your breakpoints

### Debugging Logical Replication

1. Set up replication (see README.md)

2. Set breakpoints in replication code:
   - `src/backend/replication/logical/worker.c` - Replication worker
   - `src/backend/replication/logical/launcher.c` - Worker launcher
   - `src/backend/replication/walsender.c` - WAL sender

3. Attach to the primary's postmaster or WAL sender process

4. Attach to the replica's logical replication worker:
   ```bash
   # On replica, find the worker PID
   docker compose exec postgres-replica psql -U postgres -c \
     "SELECT pid, application_name FROM pg_stat_replication;"
   ```

5. Make changes on primary and watch replication in the debugger

### Debugging Server Startup

1. Stop the containers:
   ```bash
   docker compose down
   ```

2. Set breakpoints in startup code:
   - `src/backend/postmaster/postmaster.c` - Main entry point
   - `src/backend/utils/init/postinit.c` - Backend initialization
   - `src/backend/access/transam/xlog.c` - WAL recovery

3. Start containers:
   ```bash
   docker compose up -d
   ```

4. Quickly attach debugger to the postmaster process

5. Restart PostgreSQL to hit breakpoints:
   ```bash
   docker compose exec postgres-primary pg_ctl restart -D /var/lib/postgresql/data
   ```

### Debugging Crashes

If PostgreSQL crashes, you can examine the core dump:

1. Enable core dumps in the container:
   ```bash
   docker compose exec postgres-primary bash -c "ulimit -c unlimited"
   ```

2. Configure core dump location in `postgresql.conf`:
   ```
   # Add to config/primary/postgresql.conf
   logging_collector = on
   ```

3. After a crash, find the core file:
   ```bash
   docker compose exec postgres-primary find /var/lib/postgresql/data -name "core*"
   ```

4. Load the core dump in gdb:
   ```bash
   docker compose exec postgres-primary gdb /usr/local/pgsql/bin/postgres /path/to/core
   ```

5. Examine the backtrace:
   ```
   (gdb) bt
   (gdb) frame 0
   (gdb) print variable_name
   ```

## GDB Commands Reference

### Essential Commands

```gdb
# Breakpoints
break function_name          # Set breakpoint at function
break file.c:123            # Set breakpoint at line
info breakpoints            # List all breakpoints
delete 1                    # Delete breakpoint #1
disable 1                   # Disable breakpoint #1
enable 1                    # Enable breakpoint #1

# Execution Control
continue (c)                # Continue execution
next (n)                    # Step over (next line)
step (s)                    # Step into (enter function)
finish                      # Run until current function returns
until 123                   # Run until line 123

# Inspection
print variable              # Print variable value
print *pointer              # Dereference pointer
print array[0]@10          # Print first 10 array elements
display variable            # Auto-print variable after each step
info locals                 # Show local variables
info args                   # Show function arguments

# Stack Traces
backtrace (bt)              # Show call stack
frame 3                     # Switch to frame #3
up                          # Move up one frame
down                        # Move down one frame

# Watchpoints
watch variable              # Break when variable changes
rwatch variable             # Break when variable is read
awatch variable             # Break on read or write
```

### PostgreSQL-Specific Commands

```gdb
# Print PostgreSQL structures
print *node                 # Print a Node structure
print *(Query*)node        # Cast and print as Query
print *estate              # Print executor state

# Examine memory contexts
print CurrentMemoryContext
print *CurrentMemoryContext

# Print backend state
print MyProc
print MyBackendId
print MyDatabaseId
```

## Troubleshooting

### Issue: Cannot Attach to Process

**Symptoms**: "Could not attach to process" or "Operation not permitted"

**Solutions**:
1. Verify containers have SYS_PTRACE capability:
   ```bash
   docker inspect postgres-primary | grep -A 5 CapAdd
   ```

2. Check if gdb is installed in the container:
   ```bash
   docker compose exec postgres-primary which gdb
   ```

3. Ensure the process is running:
   ```bash
   docker compose exec postgres-primary ps aux | grep postgres
   ```

### Issue: Breakpoints Not Hit

**Symptoms**: Debugger attaches but breakpoints show as "unverified"

**Solutions**:
1. Verify source code mapping in `.vscode/launch.json`:
   ```json
   "sourceFileMap": {
     "/usr/src/postgresql": "${workspaceFolder}/postgresql"
   }
   ```

2. Check that source code matches the compiled binary:
   ```bash
   docker compose exec postgres-primary postgres --version
   cat postgresql/configure.ac | grep AC_INIT
   ```

3. Ensure PostgreSQL was compiled with debug symbols (CFLAGS=-O0 in Dockerfile)

4. Try setting breakpoints after attaching:
   - Attach debugger first
   - Then set breakpoints in VS Code
   - Or use gdb console: `break function_name`

### Issue: Source Code Not Found

**Symptoms**: Debugger shows assembly instead of source code

**Solutions**:
1. Verify the postgresql/ directory contains source code:
   ```bash
   ls -la postgresql/src/backend/
   ```

2. Check VS Code settings for include paths:
   ```json
   "C_Cpp.default.includePath": [
     "${workspaceFolder}/postgresql/src/include"
   ]
   ```

3. Ensure source code is mounted in the container:
   ```bash
   docker compose exec postgres-primary ls /usr/src/postgresql
   ```

### Issue: Process Picker Shows No Processes

**Symptoms**: VS Code process picker is empty or shows no postgres processes

**Solutions**:
1. Verify containers are running:
   ```bash
   docker compose ps
   ```

2. Check if PostgreSQL is running inside the container:
   ```bash
   docker compose exec postgres-primary ps aux
   ```

3. Try using the "Debug PostgreSQL Backend Process" configuration with a specific PID

### Issue: Debugger Disconnects Immediately

**Symptoms**: Debugger attaches but immediately disconnects

**Solutions**:
1. The process may have exited - check logs:
   ```bash
   docker compose logs postgres-primary
   ```

2. Try attaching to the postmaster (parent) process instead of a backend

3. Increase timeout in launch.json:
   ```json
   "timeout": 30000
   ```

## Advanced Debugging Techniques

### Conditional Breakpoints

Set breakpoints that only trigger under specific conditions:

1. In VS Code, right-click a breakpoint and select "Edit Breakpoint"
2. Add a condition, e.g., `strcmp(relname, "pg_class") == 0`
3. The breakpoint will only trigger when the condition is true

### Logging to PostgreSQL Log

Add debug output to your code:

```c
elog(LOG, "Debug: variable value = %d", my_variable);
elog(DEBUG1, "Entering function with param = %s", param);
```

View logs:
```bash
docker compose logs -f postgres-primary
```

### Using printf Debugging

Add printf statements (they'll appear in Docker logs):

```c
fprintf(stderr, "DEBUG: reached checkpoint A\n");
fflush(stderr);
```

### Debugging with Core Dumps

For post-mortem debugging:

1. Generate a core dump manually:
   ```bash
   docker compose exec postgres-primary gcore <pid>
   ```

2. Analyze with gdb:
   ```bash
   docker compose exec postgres-primary gdb /usr/local/pgsql/bin/postgres core.<pid>
   ```

### Remote Debugging from Host

If you prefer running gdb on your host machine:

1. Install gdb-multiarch on your host:
   ```bash
   brew install gdb  # macOS
   ```

2. Start gdbserver in the container:
   ```bash
   docker compose exec postgres-primary gdbserver :2345 --attach <pid>
   ```

3. Connect from host:
   ```bash
   gdb /path/to/local/postgres
   (gdb) target remote localhost:2345
   ```

## Performance Considerations

Debugging can significantly slow down PostgreSQL:

- **Breakpoints**: Pause execution completely
- **Watchpoints**: Can be very slow (checks on every memory access)
- **Debug builds**: Run slower than optimized builds (CFLAGS=-O0)

For performance testing, use a release build without debugging symbols.

## Additional Resources

- [PostgreSQL Developer Documentation](https://www.postgresql.org/docs/current/source.html)
- [GDB Documentation](https://sourceware.org/gdb/documentation/)
- [VS Code C++ Debugging](https://code.visualstudio.com/docs/cpp/cpp-debug)
- [PostgreSQL Debugging Guide](https://wiki.postgresql.org/wiki/Developer_FAQ#Debugging)

## Tips and Best Practices

1. **Start Simple**: Begin with the postmaster process before debugging specific backends
2. **Use Logging**: Combine elog() statements with breakpoints for better context
3. **Save Configurations**: Create custom launch configurations for frequently debugged scenarios
4. **Keep Notes**: Document which functions handle which operations
5. **Test Incrementally**: Set breakpoints at high-level functions first, then drill down
6. **Watch Memory**: Use valgrind in the container for memory debugging
7. **Backup Data**: Always work with test data when debugging

## Example Debugging Session

Here's a complete example of debugging a simple query:

```bash
# 1. Start containers
docker compose up -d

# 2. Connect and get backend PID
docker compose exec postgres-primary psql -U postgres
```

```sql
-- In psql
SELECT pg_backend_pid();  -- Returns, e.g., 123
```

```bash
# 3. In VS Code:
#    - Open src/backend/executor/execMain.c
#    - Set breakpoint on ExecutorRun() function
#    - Select "Debug PostgreSQL Backend Process"
#    - Press F5, enter PID 123

# 4. Back in psql, run a query:
```

```sql
SELECT * FROM pg_class LIMIT 1;
```

```
# 5. VS Code will hit the breakpoint
#    - Inspect variables in the Variables panel
#    - Step through code with F10 (next) and F11 (step into)
#    - Use Debug Console to run gdb commands
#    - Continue with F5 when done
```

Happy debugging!
