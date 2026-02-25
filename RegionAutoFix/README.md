# RegionAutoFix

7 Days To Die region corruption auto-fix: tail server log, detect corrupt `.7rg` files, stop server, restore from backups with escalation, restart, optional Discord and telnet heartbeat.

---

## A. What it does

- **Tail server log** in real time (`tail -F`).
- **Detect** the phrase "incorrect region header" (case-insensitive) and extract the region filename (e.g. `r.-3.5.7rg`).
- **Lock** with `flock` to prevent concurrent restores.
- **Stop server** in order: telnet `shutdown` → `stopcmd` (if set) → kill by process name.
- **Restore** the corrupt region from the newest backup; if the same region fails again, escalation uses the next-older snapshot (depth tracked in state).
- **Quarantine** the live corrupt file to `State/quarantine/` before overwriting.
- **Restart** server via `startcmd` or best-effort `systemctl`/`service`.
- **Optional Discord** webhook notifications (disabled if `webhook` is empty).
- **Optional telnet heartbeat** when log has been idle > 120s; rate-limited Discord message for heartbeat.
- **Scheduled backups**: Region-only snapshots every `savetime` minutes, with retention of newest `savecount` snapshots.
- **State persistence** across restarts: last log activity, last backup time, restore depth per region, lock file.

---

## B. Requirements

- **Bash**, **coreutils** (`cp`, `ls`, `rm`, `mkdir`), **tail**, **grep**, **awk**/**sed**, **flock**, **nc** (netcat), **curl**.
- 7DTD dedicated server **log path** readable by the user running the tool.
- **Permissions**: read logfile; read/write `worldsave/Region`; create/write under backup dir; execute `stopcmd`/`startcmd` if used.
- **Linux** host recommended (where the 7DTD server runs); Windows dev is OK.

---

## C. Directory structure

```
RegionAutoFix/
  run.sh              # Entry point
  config.env          # Your config (do not commit; copy from config.env.example)
  config.env.example  # Template with placeholders
  Saves/              # Snapshot backups: Saves/snap_YYYY-MM-DD_HH-MM-SS/Region/
  Logs/               # Timestamped run logs: autofix_YYYY-MM-DD_HH-MM-SS.log
  State/              # Persisted state
    last_log_activity.ts
    last_backup.ts
    region_restore_depth.tsv   # region filename TAB depth
    restore.lock               # flock file for restore
    quarantine/                # Copies of corrupt files before overwrite
  lib/
    common.sh         # timestamp, log, die, ensure_dirs, state, list_snapshots, safe_realpath
    monitor.sh        # monitor_loop (tail log, detect corruption)
    backups.sh        # backup_loop, run_one_backup
    restore.sh        # restore_region, depth, stop/start helpers
    telnet.sh         # telnet_send
    discord.sh        # discord_send
```

- **Saves/** holds timestamped Region-only snapshots; retention keeps the newest `savecount`.
- **Logs/** gets one new log file per `run.sh` start; all stdout/stderr go there.
- **State/** holds timestamps, restore depth per region, and the lock file; **quarantine/** keeps a copy of each corrupt file before it is replaced.

---

## D. Installation

1. **Clone the repo** (if not already):
   ```bash
   git clone <repo-url> RegionHealer-v2 && cd RegionHealer-v2
   ```

2. **Copy config template** (never commit real config):
   ```bash
   cp RegionAutoFix/config.env.example RegionAutoFix/config.env
   ```

3. **Edit `RegionAutoFix/config.env`** with your paths and options (see Configuration below).

4. **Make scripts executable**:
   ```bash
   chmod +x RegionAutoFix/run.sh RegionAutoFix/lib/*.sh
   ```

5. **Create directories** (optional; the tool creates them if missing):
   ```bash
   mkdir -p RegionAutoFix/Saves RegionAutoFix/Logs RegionAutoFix/State/quarantine
   ```

6. **Optional**: Set `webhook` for Discord notifications; set `telnet` and optionally `telnet_password` for shutdown and heartbeat.

---

## E. Configuration

All keys are shell-compatible `key="value"` in `config.env`. Derived path: **`region_dir="$worldsave/Region"`**.

| Key | Description | Example |
|-----|-------------|---------|
| `worldsave` | Path to world save (parent of `Region`) | `"/path/to/7DaysToDie/Saves/WorldName/WorldName"` |
| `backup` | Base dir for snapshots | `"/path/to/RegionAutoFix/Saves"` |
| `username` | OS user running 7DTD (for pgrep/kill) | `"linuxuser"` |
| `savetime` | Minutes between Region-only backups | `"60"` |
| `savecount` | Number of snapshots to retain | `"24"` |
| `logfile` | Full path to 7DTD server console log | `"/path/to/sdtdserver-console.log"` |
| `webhook` | Discord webhook URL; **empty = Discord disabled** | `"https://discord.com/api/webhooks/..."` or `""` |
| `telnet` | Telnet port (e.g. 8081) | `"8081"` |
| `startcmd` | Optional: command to start server | `"/path/to/start.sh"` or `""` |
| `stopcmd` | Optional: command to stop server | `"/path/to/stop.sh"` or `""` |
| `heartbeat_cmd` | Telnet command when idle (default `version`) | `"version"` |
| `telnet_password` | Optional: telnet admin password | `""` or `"mypass"` |
| `telnet_timeout` | nc timeout in seconds (2–5) | `"5"` |
| `dry_run` | If `"true"`: no stop/start/kill, no file overwrite; still logs and Discord | `"false"` |

- **Discord**: If `webhook` is empty, `discord_send` is a no-op.
- **region_dir** is not set in config; it is derived as `"$worldsave/Region"`.

---

## F. Usage

**Run:**
```bash
./RegionAutoFix/run.sh
```

- On start, the tool creates **`Logs/autofix_YYYY-MM-DD_HH-MM-SS.log`** and redirects all stdout/stderr to it. Every log line is timestamped.
- Three loops run in parallel: log monitor, backup scheduler, idle watcher. The process runs until killed.
- **State** is persisted in `State/`: `last_log_activity.ts`, `last_backup.ts`, `region_restore_depth.tsv`, `restore.lock`.

**Dry run:** Set `dry_run="true"` in `config.env`. The tool will not stop/start/kill the server or overwrite region files; it will log what it would do and can still send Discord messages.

---

## G. Systemd service (optional)

Example unit file. Replace `<repo>`, `<username>`, and paths as needed.

```ini
[Unit]
Description=RegionAutoFix for 7DTD
After=network.target

[Service]
Type=simple
User=<username>
WorkingDirectory=<repo>/RegionAutoFix
ExecStart=/usr/bin/env bash -lc './run.sh'
Restart=always
RestartSec=10
# Tool logs to its own file under Logs/; these go to journal as well
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

- **Enable and start:**
  ```bash
  sudo cp regionautofix.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable regionautofix
  sudo systemctl start regionautofix
  ```
- The tool writes its own timestamped log under `RegionAutoFix/Logs/`; systemd will also capture stdout/stderr in the journal.

---

## H. Troubleshooting

| Issue | What to check |
|-------|----------------|
| **logfile not found / permission denied** | Ensure `logfile` path exists (or its parent dir) and the run user can read it. The monitor waits for the file to appear if missing at start. |
| **nc / telnet not responding** | Check `telnet` port and firewall; if using `telnet_password`, ensure it’s correct. Timeout is 2–5s (`telnet_timeout`). |
| **No snapshots available** | At least one backup must run before a restore. Wait for the first backup (after `savetime` minutes) or run with backups enabled and no `dry_run`. |
| **Repeated corruption and escalation depth** | Each failure for the same region increments depth (tries older snapshot). If all snapshots are bad or missing, you’ll see "No valid backup found". Add good backups or fix the region manually. |
| **Restore lock stuck** | If a restore crashed while holding the lock, delete the lock file: `rm -f RegionAutoFix/State/restore.lock`. Ensure no other `run.sh` or restore is running before removing. |
| **Backup retention not pruning** | Check write permissions on `backup` (Saves) and that `savecount` is set. Old snapshots are removed after each backup. |

---

## I. Safety / Operational notes

- **Restores only** files matching the region pattern (e.g. `r.*.7rg`), with path validation so the target stays under `region_dir`. No slashes in filenames.
- **Quarantine**: Before overwriting, the live (corrupt) file is copied to `State/quarantine/<region>_<timestamp>.7rg`.
- **Never deletes** the live region file without replacing it: restore uses `cp -a` from backup to the live path.
- **Backups** are Region-only (`cp -a "$region_dir" "$snap/Region"`); full world backup is out of scope.
- **Recommendation**: Test with `dry_run="true"` first. Run the tool on the same Linux host where the 7DTD server runs.

---

## J. FAQ

**Why only Region folder backups?**  
To keep backups small and fast; region files are where "incorrect region header" corruption appears. Full world backup can be handled separately.

**How does escalation depth work?**  
For each region file, the tool tracks a depth (default 1). Depth N means "use the Nth newest snapshot". After a successful restore, depth is incremented so the next time that region corrupts, an older snapshot is tried.

**How do I reset escalation depth for one region?**  
Edit `State/region_restore_depth.tsv`: delete the line for that region file, or set its second column to `1`. Format is `regionfile<TAB>depth`.
