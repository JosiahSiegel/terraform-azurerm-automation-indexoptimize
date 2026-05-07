# Minimal example

The simplest working deployment: one Automation Account, one target database,
one weekly schedule.

## What this creates

- A resource group (`rg-indexopt-example`)
- An Automation Account (`example-indexopt-auto`) with SystemAssigned MI
- The built-in `IndexOptimize` runbook (PowerShell 7.2)
- The pinned `SqlServer 22.3.0` PS module imported into the PS 7.x slot
- One weekly schedule firing every Saturday at 03:00 ET against
  `myserver.database.windows.net` / `MyDatabase`

## Apply it

```bash
terraform init
terraform plan
terraform apply
```

## One-time SQL setup

After apply, on the target database **as the Entra admin** (the user/group
you've configured as the Azure SQL Server's Microsoft Entra admin):

```sql
CREATE USER [example-indexopt-auto] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [example-indexopt-auto];
```

## Smoke-test

In the Azure portal, navigate to **Automation Account →
example-indexopt-auto → Runbooks → IndexOptimize → Start**, set parameters:

- `sqlserver` = `myserver.database.windows.net`
- `database` = `MyDatabase`

Watch the job streams. Successful run produces (in order):

```
Connected to myserver.database.windows.net / MyDatabase as managed identity.
Phase 1: opportunistic cleanup of any sentinel-tagged orphans...
Phase 2: ownership state - IndexOptimize=absent, CommandExecute=absent
Phase 3: installing CommandExecute and IndexOptimize from embedded vendored Ola source.
Phase 4: executing dbo.IndexOptimize against MyDatabase on myserver.database.windows.net.
IndexOptimize completed successfully.
Cleanup: dropping sentinel-tagged procs we installed this run.
```

Verify zero leftovers:

```sql
SELECT name FROM sys.objects WHERE type = 'P' AND name IN ('IndexOptimize','CommandExecute');
-- (no rows expected)
```

## Customizing

- Change `sql_server` / `database` to point at your real Azure SQL DB.
- Add more entries to `index_optimize_targets` to onboard more databases.
- Change `week_days` and `start_time` to control the schedule.
- See the root [README](../../README.md) for full input reference and the
  with-failure-alerting submodule.
