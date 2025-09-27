# 🧩 Koronet-Axerrio.GitTools

Koronet-Axerrio.GitTools is a PowerShell module that manages Git feature-branch workflows
for SQL-based development at Koronet/Axerrio.  
It automates branch creation, auditing, harvesting, and pull-request preparation — tightly integrated with the database DDL audit system.

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

```bat
:: === Recommended quick install ===
Install-KXGTLatest.bat

:: === Optional clean reinstall ===
Uninstall-KXGTLocal.bat -RemoveConfig
Install-KXGTLatest.bat
