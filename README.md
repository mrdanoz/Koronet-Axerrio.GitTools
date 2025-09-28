# 🧩 Koronet-Axerrio.GitTools

Koronet-Axerrio.GitTools is a PowerShell module that manages Git feature-branch workflows  
for SQL-based development at **Koronet/Axerrio**.  
It automates branch creation, auditing, harvesting, and pull-request preparation —  
tightly integrated with the database DDL audit system.

---

## 📑 Table of Contents
- [Installation](#installation)
- [Clean Uninstall](#clean-uninstall)
- [Manual Install (Offline)](#manual-install-offline)
- [Configuration](#configuration)
- [Verification](#verification)
- [Files Included in the Release](#files-included-in-the-release)
- [Support](#support)

---

## 🚀 Installation

The module is distributed via GitHub **Releases** as a ready-to-install package.  
Developers can install or update it using the provided batch scripts or manually.

### 🧭 Quick Install (recommended)

1. Download or clone this repository.  
2. Open a command prompt and run:

    Install-KXGTLatest.bat

This script will:

- Detect PowerShell 7 (pwsh.exe) or fall back to Windows PowerShell 5.1  
- Download the latest release ZIP from GitHub  
- Extract it to your user’s PowerShell Modules folder  
  - PS 7 → Documents\PowerShell\Modules  
  - PS 5.1 → Documents\WindowsPowerShell\Modules  
- Import the module and confirm successful installation  

Re-running Install-KXGTLatest.bat will always update to the newest release automatically.

---

## 🧹 Clean Uninstall

If you’ve tested earlier versions, run this first to remove all local copies (including any under OneDrive)  
and optionally clear the configuration file:

    Uninstall-KXGTLocal.bat -RemoveConfig

- -RemoveConfig deletes your local JSON configuration, so the module will prompt you for new values on the next run.  
- No admin rights are required unless you previously installed the module system-wide.

---

## 📦 Manual Install (Offline)

If you can’t use the batch installer:

1. Download the latest release ZIP from  
   https://github.com/mrdanoz/Koronet-Axerrio.GitTools/releases

2. Unblock and extract it:

    Unblock-File "$env:USERPROFILE\Downloads\Koronet-Axerrio.GitTools-v0.10.1.zip"  
    Expand-Archive "$env:USERPROFILE\Downloads\Koronet-Axerrio.GitTools-v0.10.1.zip" `
    -DestinationPath "$env:USERPROFILE\Documents\PowerShell\Modules" -Force

3. Import and verify:

    Import-Module Koronet-Axerrio.GitTools -Force  
    Get-Command -Module Koronet-Axerrio.GitTools

---

## ⚙️ Configuration

On first use, the module checks for a local JSON configuration file.  
If it doesn’t exist, it will prompt you to create one interactively.

You can also create or reset it manually:

    Initialize-KXGTConfig

### Current JSON layout (v0.10.x and later)

    {
      "defaultRepoPath": "V:\\Working\\DH\\abs-erp",
      "remoteRepoUrl":  "https://github.com/your-org/abs-erp.git",
      "defaultBaseBranch": "develop",
      "auditServer": "SQLDEV01",
      "auditDatabase": "ABSDEV",
      "auditSchema": "dba",
      "appNamePrefix": "KXGT-DEV-",
      "defaultAppName": "KXGT-DEV-DH"
    }

**Notes**
- The configuration is local per developer — it is not stored in Git or in dba.Developer.  
- dba.Developer now tracks only user identification  
  (DisplayName, LoginName, GitHandle, EmailAddress, IsActive, etc.)  
  and no longer contains a RepoPath column.  
- All repository paths are resolved from defaultRepoPath in this JSON file.

To view or verify your current configuration:

    Get-KXGTConfig

---

## 🧪 Verification

After installation, confirm the module is loaded:

    Get-Module Koronet-Axerrio.GitTools -ListAvailable

Expected output:

    ModuleType Version Name                        ExportedCommands
    ---------- ------- ----                        ----------------
    Script     0.10.1  Koronet-Axerrio.GitTools    {Get-KXGTConfig, New-KXGTFeatureBranch, New-KXGTPullRequest, Complete-KXGTPullRequest, Invoke-KXGTPush}

Test a basic operation:

    New-KXGTFeatureBranch -FeatureName "Test-Feature" -WhatIf

If no errors appear, the installation and configuration are correct.

---

## 📦 Files Included in the Release

| File | Purpose |
|------|----------|
| **Koronet-Axerrio.GitTools-vX.Y.Z.zip** | Main module package |
| **tools/KXGT-Bootstrap.ps1** | Stand-alone PowerShell bootstrapper (optional) |
| **tools/Install-KXGTLatest.bat** | One-click installer (recommended) |
| **tools/Uninstall-KXGTLocal.bat** | Full uninstaller / config reset |

---
---

## 📁 Recommended Module Location

### 🧠 Why use the local *Documents* folder
- ✅ **Stable path** — not affected by OneDrive renaming (`Documenten` / `Documents`)
- ✅ **Offline-friendly** — works even if OneDrive is paused or disconnected
- ✅ **No file locks** — OneDrive sync can lock `.ps1` / `.psm1` files
- ✅ **Predictable** — same path for all developers, simplifies scripts and automation

### ☁️ If your company enforces OneDrive
If your *Documents* folder is automatically redirected to OneDrive, this module still works,  
but you should verify that PowerShell can see it. Run this once in PowerShell 7:

```powershell
# Ensure PowerShell 7 includes your user modules path
$modPath = "$HOME\Documents\PowerShell\Modules"
if ($env:PSModulePath -notmatch [regex]::Escape($modPath)) {
  $env:PSModulePath = "$modPath;$env:PSModulePath"
}
---

## 🆘 Support

If installation or configuration fails:

1. Run Uninstall-KXGTLocal.bat to clean old versions  
2. Reinstall with Install-KXGTLatest.bat  
3. If issues persist, open an issue on GitHub or contact the DBA/DevOps maintainer

## 🧩 Troubleshooting: Module not visible in PowerShell 7

If `Import-Module Koronet-Axerrio.GitTools` runs without errors but  
`Get-Command -Module Koronet-Axerrio.GitTools` shows no functions, the module is installed correctly but **PowerShell 7 is not scanning the correct folder**.

This usually happens on Windows Server 2012 R2 or on systems where  
`$env:PSModulePath` has been overridden (for example, pointing to a network share or the old *WindowsPowerShell* folder).

---

### ✅ Quick fix – current session only

Run this in PowerShell 7 (**pwsh**) to restore the default module search paths:

```powershell
$defaults = @(
  "$HOME\Documents\PowerShell\Modules",
  "$env:ProgramFiles\PowerShell\Modules",
  "$env:ProgramFiles\WindowsPowerShell\Modules",
  "$PSHOME\Modules"
)
$custom = $env:PSModulePath -split ';' | Where-Object { $_ -and ($_ -notin $defaults) }
$env:PSModulePath = ($defaults + $custom) -join ';'

---

**Version:** 0.10.1  
**Maintainer:** Koronet / Axerrio DevOps  
**License:** Internal use only
