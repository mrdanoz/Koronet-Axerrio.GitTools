# Koronet-Axerrio.GitTools — README

A PowerShell 7+ toolkit for **database‑first** development on SQL Server, with automatic harvesting of audited DDL changes into a Git repository and one‑command pull‑request flows.

> **Model**: The **database is the source of truth**. Developers make changes directly in DEV; an audit trigger logs DDL. The Harvester turns those audited changes into repository updates (re‑script CREATE/ALTER objects, delete files on DROP) and then drives a standard PR process.

---

## Table of contents
1. [What this does](#what-this-does)
2. [Prerequisites](#prerequisites)
3. [Install / Import](#install--import)
4. [Configuration](#configuration)
   - [Initialize-KXGTConfig](#initialize-kxgtconfig)
   - [Get-KXGTConfig / Invoke-KXGTGetConfig](#get-kxgtconfig--invoke-kxgtgetconfig)
   - [Test-KXGTConfig](#test-kxgtconfig)
   - [Repair-KXGTRepoLayout](#repair-kxgtrepolayout)
5. [Database objects expected](#database-objects-expected)
6. [Repo layout](#repo-layout)
7. [Harvester](#harvester)
   - [How it decides what to change](#how-it-decides-what-to-change)
   - [Safety flags](#safety-flags)
8. [Standard PR flow](#standard-pr-flow)
9. [Command reference](#command-reference)
10. [Typical end‑to‑end workflow](#typical-end-to-end-workflow)
11. [Troubleshooting](#troubleshooting)

---

## What this does
- **Harvest audited DDL** for a given **Branch + AppName** from `dba.DDL_Audit`:
  - For **CREATE/ALTER**: (re)script the **full object definition** into the repo (table → includes indexes/constraints; procs/views/functions → full body; triggers/sequences/synonyms/types supported).
  - For **DROP**: remove the matching `schema.object.sql` from the repo.
- **Generate reports** (optional): SQL bundle, JSON, CSV with the raw audit rows.
- Provide a **one‑command PR flow**:
  - Ensure/switch to branch → harvest → stage/commit → push → create PR (GitHub or Azure DevOps) → optional auto‑merge.
- Validate and prepare your environment: load config, test SQL connectivity, check/repair repo folder layout.

## Prerequisites
- **PowerShell 7+**
- **SqlServer** PowerShell module (SMO + `Invoke-Sqlcmd`):
  ```powershell
  Install-Module SqlServer -Scope CurrentUser
  ```
- **git** on PATH
- Optional for PR creation:
  - **GitHub CLI** (`gh`) **or**
  - **Azure DevOps CLI** (`az` with devops extension) and defaults configured
- Database‑side audit in place (see [Database objects expected](#database-objects-expected)).

## Install / Import
Place the module folder somewhere in `$env:PSModulePath` (or import by path) and:
```powershell
Import-Module Koronet-Axerrio.GitTools
```

---

## Configuration
All commands read defaults from **`kxgt.config.json`**, with environment variable overrides.

### Initialize-KXGTConfig
Create a new config at **Repo**, **User**, or **Module** scope.

```powershell
Initialize-KXGTConfig -Scope Repo `
  -RepoPath 'V:\Working\ABS\database' `
  -ServerInstance 'sql-dev\inst1' `
  -Database 'ABSDEV' `
  -ProjectLayout SSDT `
  -Verbose
```

**Config file keys** (PascalCase):
```json
{
  "ServerInstance": "sql-dev\\inst1",
  "Database": "ABSDEV",
  "RepoPath": "V:\\Working\\ABS\\database",
  "ProjectLayout": "SSDT"
}
```

Scopes resolve in this order (first hit wins):
1. Repo: `<RepoPath>\.kxgt\kxgt.config.json`
2. User: Windows `%APPDATA%\KXGT\kxgt.config.json` or Linux/macOS `~/.config/kxgt/kxgt.config.json`
3. Module: `<module folder>\kxgt.config.json`

**Env overrides** (optional; great for CI): `KXGT_SERVER`, `KXGT_DATABASE`, `KXGT_REPOPATH`, `KXGT_LAYOUT`.

### Get-KXGTConfig / Invoke-KXGTGetConfig
Load the effective configuration (after scope resolution + env overrides):
```powershell
$cfg = Get-KXGTConfig
$cfg
```

### Test-KXGTConfig
Validate SQL connectivity, repo existence, and (optionally) folder layout:
```powershell
# Basic check
Test-KXGTConfig -Verbose

# Require repo + verify SSDT/Flat folders exist
Test-KXGTConfig -RequireRepo -CheckRepoLayout -Verbose
```
Returns a summary object with `Ok`, `ServerOk`, `RepoOk`, `LayoutOk`, `MissingFolders`, and notes.

### Repair-KXGTRepoLayout
Create any missing folders for the configured (or forced) layout. Supports `-WhatIf` and `.gitkeep` creation.
```powershell
Repair-KXGTRepoLayout -GitKeep -Verbose
```

---

## Database objects expected
The Harvester relies on these tables in your DEV database (names can be adjusted in code if needed):

- `dba.DDL_Audit` — the DDL audit sink; minimally contains:
  - `AuditID`, `PostTime`, `EventType` (`CREATE`|`ALTER`|`DROP`), `ObjectType`, `SchemaName`, `ObjectName`, `DatabaseName`, `TSQL`, `LoginName`, `OriginalLoginName`, `AppName`, `HostName`, `SessionID`, `Succeeded`.
- `dba.FeatureBranch` — branch metadata (`FeatureBranchID`, `Branch`, `AppName`, ...).
- `dba.FeatureBranchUser` — links branch to logins (`FeatureBranchID`, `LoginName`, `ClosedAt` nullable).
- `dba.Developer` — resolves current user from git identity (optional, but recommended): at least `LoginName`, `GitHandle` and/or `Email`, optional `RepoPath`.

The Harvester filters audit rows by **Branch + AppName**, constrained by users in `FeatureBranchUser`; it may further narrow to the current developer by resolving git identity against `dba.Developer`.

---

## Repo layout
Two opinionated layouts are supported (adjust paths in code if yours differs):

**SSDT (default)**
```
Tables/
Views/
Programmability/Stored Procedures/
Programmability/Functions/
Programmability/Triggers/
Programmability/Sequences/
Programmability/Types/
Synonyms/
```

**Flat**
```
Tables/  Views/  Procs/  Functions/  Triggers/  Sequences/  Types/  Synonyms/
```

Each object is stored as `schema.object.sql` in the appropriate folder.

---

## Harvester
**Command**: `Invoke-KXGTHarvest`

**Minimal call** (all context from config & developer table):
```powershell
Invoke-KXGTHarvest -AppName 'ABS' -Branch 'feature/KOR-123' -ApplyDrops -Verbose
```

**What it does**
1. Loads config via `Get-KXGTConfig` (ServerInstance, Database, RepoPath, ProjectLayout).
2. Optionally resolves your **LoginName** via `dba.Developer` (from `git config user.email/name`) to narrow audit to *your* changes within the branch.
3. Pulls rows from `dba.DDL_Audit` for **AppName + Branch** (and Succeeded=1), ordered by `PostTime`.
4. Reduces to the **latest change per object** (type + schema + name).
5. For each latest row:
   - **DROP** → remove matching `schema.object.sql` from the repo (with `-ApplyDrops`, else only logs what would happen).
   - **CREATE/ALTER** → **(re)script the live object from the database** into `schema.object.sql` using SMO with:
     - `DriAll = $true` (keys/constraints)
     - `Triggers = $true`, `Indexes = $true`, `Permissions = $true`
     - Schema‑qualified names, batch terminator, ANSI padding
6. Optionally writes **reports** to `_harvest/<branch>/<timestamp>`:
   - `changes_<branch>.sql` (bundle of raw audited TSQL)
   - `changes_<branch>.json`
   - `changes_<branch>.csv`

It returns an object with `Changes` (raw audit rows), `Scripted` (files written), `DropDeletions` (files deleted), `OutDir`, etc.

### How it decides what to change
- Multiple audit hits for the same object are **deduplicated**; the **last** by `PostTime` wins.
- Scripting targets the **current state in the database** (database‑first); if you ALTER a table 3×, you get one re‑script with the final definition.

### Safety flags
- **`-WhatIf` / `-Confirm`**: honored for file writes and deletes.
- **`-ApplyDrops`**: required to actually delete files on DROP; otherwise only logs what would be removed.
- **`-ScriptCreatesAndAlters:$false`** (advanced): disable scripting when you only want reports.

---

## Standard PR flow
**Command**: `Invoke-KXGTStandardPRFlow`

One command to harvest, commit, push, and open a PR.

```powershell
Invoke-KXGTStandardPRFlow `
  -RepoPath 'V:\Working\ABS\database' `
  -ServerInstance 'sql-dev\inst1' `
  -Database 'ABSDEV' `
  -Branch 'feature/KOR-123' `
  -BaseBranch 'develop' `
  -AppName 'ABS' `
  -ApplyDrops `
  -WriteSqlBundle -WriteJson -WriteCsv `
  -Provider Auto `
  -Reviewers @('alice','bob') `
  -AutoMerge -MergeMethod merge `
  -Verbose
```

**What it does**
1. `git fetch --all --prune` (best‑effort), checkout/create feature branch from base.
2. Calls **`Invoke-KXGTHarvest`** (so CREATE/ALTER get scripted, DROP files are deleted when `-ApplyDrops`).
3. `git add --all` → generate commit message (includes counts) → commit if there’s staged work.
4. Push with upstream if needed.
5. Create PR via **GitHub CLI** (`gh`) or **Azure DevOps** (`az repos pr create`), depending on availability or explicit `-Provider`.
6. Optionally enable auto‑merge/auto‑complete.

**Notes**
- Provider detection: `Auto` → prefer GitHub if `gh` exists; else Azure DevOps if `az` exists; otherwise GitHub (with warning if CLI missing).
- Only commits when there is staged work (`git diff --cached --quiet`).

---

## Command reference

### `Initialize-KXGTConfig`
Create a new config file at the chosen scope.
```powershell
Initialize-KXGTConfig -Scope Repo -RepoPath <path> -ServerInstance <srv> -Database <db> -ProjectLayout SSDT
```

### `Get-KXGTConfig` / `Invoke-KXGTGetConfig`
Return the effective config.
```powershell
Get-KXGTConfig
```

### `Test-KXGTConfig`
Connectivity + repo/layout checks.
```powershell
Test-KXGTConfig -RequireRepo -CheckRepoLayout -Verbose
```

### `Repair-KXGTRepoLayout`
Create missing folders for SSDT/Flat.
```powershell
Repair-KXGTRepoLayout -GitKeep -Verbose
```

### `Invoke-KXGTHarvest`
Harvest audit rows and synchronize repo files.
```powershell
Invoke-KXGTHarvest -AppName <app> -Branch <branch> -ApplyDrops -Verbose
# Optional reports
Invoke-KXGTHarvest -AppName <app> -Branch <branch> -WriteSqlBundle -WriteJson -WriteCsv
```
Parameters (common):
- `-AppName` *(string, required)*
- `-Branch` *(string, required)*
- `-RepoPath` *(string, optional override)*
- `-ProjectLayout` *(SSDT|Flat, optional override)*
- `-ApplyDrops` *(switch)* → actually delete files on DROP
- `-WriteSqlBundle` / `-WriteJson` / `-WriteCsv` *(switches)*
- `-WhatIf` / `-Confirm` supported

### `Invoke-KXGTStandardPRFlow`
End‑to‑end branch → harvest → commit → push → PR.
```powershell
Invoke-KXGTStandardPRFlow -RepoPath <path> -ServerInstance <srv> -Database <db> -Branch <branch> -BaseBranch develop -AppName <app> -ApplyDrops -Provider Auto -Verbose
```

---

## Typical end‑to‑end workflow
1. **Once per repo**: `Initialize-KXGTConfig -Scope Repo ...` → `Repair-KXGTRepoLayout -GitKeep` → `Test-KXGTConfig -RequireRepo -CheckRepoLayout`.
2. **Create feature branch**: use the PR flow (it will create the branch if missing).
3. **Make DB changes** in DEV (database‑first). The audit logs your DDL.
4. **Run PR flow**:
   ```powershell
   Invoke-KXGTStandardPRFlow -RepoPath <repo> -ServerInstance <srv> -Database <db> -Branch <feature> -BaseBranch develop -AppName <app> -ApplyDrops -Verbose
   ```
5. Review PR → merge.

**Alternative**: If you want to inspect only, run the Harvester directly to generate reports without touching files.

---

## Troubleshooting
- **`Invoke-Sqlcmd: invalid 'var=value'`** — ensure the Harvester passes variables as `-Variable @("name=value",...)`. The module does this already.
- **SMO scripting finds no object** — the latest audit row is CREATE/ALTER but the object was dropped afterwards; or schema/type mapping doesn’t match your repo; verify in DEV.
- **File path mapping differs from your repo** — adjust the mapping in `Get-KXGTObjectFilePath` to your folder structure.
- **PR creation skipped** — install `gh` (GitHub) or `az` (Azure DevOps) and ensure you’re authenticated; or set `-Provider` explicitly.
- **Large audits** — the Harvester deduplicates by object and uses the **latest** row to avoid redundant scripting.

---

*© Koronet-Axerrio.GitTools — PowerShell 7+.*

