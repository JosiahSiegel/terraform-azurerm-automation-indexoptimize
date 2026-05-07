# Vendored Ola Hallengren Source — Reference Snapshot

## What's in this folder

- `MaintenanceSolution.sql` — full upstream snapshot of Ola Hallengren's
  SQL Server Maintenance Solution. **Reference only — not deployed.**
- `LICENSE.md` — Ola's MIT license, retained per the license terms.
- `README.md` — this file.

## Why this is a reference snapshot, not the deployed asset

The IndexOptimize runbook authenticates with managed identity, installs
Ola's `dbo.CommandExecute` and `dbo.IndexOptimize` procedures on the target
database, runs IndexOptimize, then drops them again — leaving no objects
behind. See `../IndexOptimize.ps1` for the orchestration logic.

Azure Automation runbooks deploy as a **single .ps1 file** with no aux-file
support at runtime, so the SQL bodies for those two procedures are embedded
directly inside `IndexOptimize.ps1` as PowerShell here-strings. The full
`MaintenanceSolution.sql` snapshot lives here so reviewers and future
maintainers have a clean diff target when refreshing the embedded SQL.

## Refresh procedure

When Ola publishes a new version:

1. Replace `MaintenanceSolution.sql` with the latest from
   <https://ola.hallengren.com/scripts/MaintenanceSolution.sql>.
2. Locate the `CommandExecute` proc block (between `SET ANSI_NULLS ON` /
   `GO` headers preceding `[dbo].[CommandExecute]` and the closing `GO`).
3. Locate the `IndexOptimize` proc block similarly.
4. Replace the contents of the `$CommandExecuteSql` and `$IndexOptimizeSql`
   here-strings in `../IndexOptimize.ps1` with the extracted blocks.
5. Update the `# Ola version:` comment at the top of `IndexOptimize.ps1`
   to match the `Version:` header in the new `MaintenanceSolution.sql`.
6. Smoke-test by manually triggering one runbook job per environment.

## What we deploy at runtime, in order

0. Authenticate. The wrapper imports the `SqlServer` PowerShell module
   (auto-installed in the PS7.x module slot by the `enable_index_optimize`
   path of the parent module) to load `Microsoft.Data.SqlClient`, then opens
   a connection with `Authentication=Active Directory Managed Identity` and
   `Encrypt=Strict`. The driver pulls the token from IMDS internally — no
   `Az.Accounts`, no `Connect-AzAccount`, no `Get-AzAccessToken` (whose
   `Token` property became a `SecureString` in Az.Accounts ≥ 4.0).
1. Opportunistic startup cleanup — drops any sentinel-tagged orphan procs
   left behind by a prior crashed run.
2. Ownership detection — checks `sys.extended_properties` for our sentinel
   `ephemeral_runbook_install` on `dbo.IndexOptimize` and `dbo.CommandExecute`.
3. Decision tree:
   - If procs absent → install + tag → run → finally drop.
   - If procs present and tagged ours → drop, reinstall + tag (refresh to
     pinned version) → run → finally drop.
   - If procs present without tag → assume manual install, leave alone,
     run, do **not** drop.
4. Run `EXECUTE dbo.IndexOptimize` with the configured parameters.
5. `finally` block — sentinel-gated drop for both procs.

## License attribution

Per the MIT license terms, the copyright notice and permission notice
appear in `LICENSE.md` and are also embedded as a header comment in
`../IndexOptimize.ps1` directly above the SQL here-strings.
