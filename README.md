# Real AI for Windows

Real AI is a 64-bit Windows desktop application built with Windows Forms and .NET Framework 4.7.2.

## Build and package

On a 64-bit Windows build machine, install Visual Studio 2022 Build Tools with the **.NET desktop build tools** workload. Run this from the repository root in Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Windows.ps1
```

The script restores the pinned .NET Framework 4.7.2 reference assemblies and System.Data.SQLite 1.0.119 dependency from NuGet, builds the Release configuration as x64, and creates a portable application folder and ZIP archive. An installed .NET Framework 4.7.2 Developer Pack can be used instead of restoring the reference assemblies.

GitHub Actions also builds this ZIP on pushes and pull requests to `main`. Download the `RealAI-PC-win-x64` artifact from the completed **Build Windows app** workflow run, or run the workflow manually with **Actions → Build Windows app → Run workflow**.

- `artifacts\RealAI-PC-win-x64\`
- `artifacts\RealAI-PC-win-x64.zip`

Distribute the ZIP archive. On a target PC, extract it and run `Real AI.exe`. Windows x64 and the .NET Framework 4.7.2 runtime (or a later in-place .NET Framework 4.x release) are required; the app and SQLite x64 native library are included in the archive. No installer or administrator privileges are required. Application data is stored under the current user's `%APPDATA%\RealAI` folder.
