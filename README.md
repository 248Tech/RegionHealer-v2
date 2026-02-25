# RegionHealer-v2

Auto-detect **"incorrect region header"** in 7 Days To Die dedicated server logs and auto-restore corrupt `.7rg` region files from backups.

**RegionAutoFix** is the shell-first subtool in this repo: it tails the server log, detects corruption, stops the server safely, restores from the newest backup (with escalation to older backups on repeated failures), and restarts the server. Optional Discord webhooks and telnet heartbeats are supported.

- **Shell-first**: Bash + coreutils, `tail`, `grep`, `awk`/`sed`, `flock`, `nc`, `curl`. Minimal dependencies.
- **Linux target**: Runtime expects a Linux environment with these utilities. Development on Windows is fine; run the tool on the same host (or an accessible host) where the 7DTD server runs.

---

## Quick Start

1. **Clone the repo**
   ```bash
   git clone https://github.com/248Tech/RegionHealer-v2 RegionHealer-v2 && cd RegionHealer-v2
   ```

2. **Create config from template**  
   Copy the example config so you don't commit secrets:
   ```bash
   cp RegionAutoFix/config.env.example RegionAutoFix/config.env
   ```

3. **Edit `RegionAutoFix/config.env`**  
   Set at least: `worldsave`, `backup`, `logfile`, and optionally `webhook`, `telnet`, `startcmd`/`stopcmd`. See [RegionAutoFix/README.md](RegionAutoFix/README.md) for all options.

4. **Ensure directories exist**  
   The tool creates `Saves/`, `Logs/`, and `State/` as needed; you can create them manually if you prefer.

5. **Make scripts executable**
   ```bash
   chmod +x RegionAutoFix/run.sh RegionAutoFix/lib/*.sh
   ```

6. **Run**
   ```bash
   ./RegionAutoFix/run.sh
   ```
   Logs go to `RegionAutoFix/Logs/autofix_YYYY-MM-DD_HH-MM-SS.log`.

7. **Optional**: Use `dry_run="true"` in config to test without stopping the server or overwriting files.

8. **Full details**: Install steps, configuration reference, systemd, troubleshooting, and safety notes are in **[RegionAutoFix/README.md](RegionAutoFix/README.md)**.

---

## Security / Secrets

- **Do not commit `RegionAutoFix/config.env`.** It may contain paths, Discord webhook URLs, and telnet passwords.
- Use **`RegionAutoFix/config.env.example`** as the tracked template with placeholder values and comments.
- Copy to `config.env` locally and add `RegionAutoFix/config.env` to `.gitignore` so it is never committed.
