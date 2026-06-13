# powershell_scripts

## Swiss‑Quality PowerShell Scripts

A small, opinionated collection of Swiss‑made PowerShell scripts for hands‑on IT admins, SREs and lab geeks.  
Automation helpers, troubleshooting utilities, hardening snippets and quality‑of‑life tools for Windows environments.

## About this repository

This repo groups together public PowerShell scripts written and used by **Emanuel De Almeida** (https://www.navanem.com).  
Most scripts are born from real‑world issues: remote service restarts, quick audits, small fixes and repeatable admin tasks.

Each script:

- Lives in its own `.ps1` file  
- Tries to follow PowerShell best practices (`[CmdletBinding()]`, proper parameter sets, `-WhatIf` / `-Confirm` when it makes sense)  
- Includes comments, examples and a short help block (`.SYNOPSIS`, `.EXAMPLE`, etc.)

## Example: Restart‑RemoteService

One of the included scripts, `Restart-RemoteService.ps1`, provides a function that:

- Pings remote servers before touching services  
- Restarts one or more services on one or more servers  
- Can send HTML email notifications on success or failure  
- Accepts pipeline input for batch operations and honours `-WhatIf` / `-Confirm`

Check each script’s header and inline help for details and usage examples.

## Getting started

1. Clone this repository:

   ```bash
   git clone https://github.com/<your-account>/powershell_scripts.git
   cd powershell_scripts
   ```

2. Unblock the scripts if needed:

   ```powershell
   Get-ChildItem *.ps1 | Unblock-File
   ```

3. Dot‑source the script you want to use:

   ```powershell
   . .\Restart-RemoteService.ps1
   Restart-RemoteService -ComputerName 'SERVER01' -ServiceName 'Spooler' -WhatIf
   ```

4. Read the `.SYNOPSIS`, `.DESCRIPTION` and `.EXAMPLE` blocks at the top of each file before running anything in production.

## Requirements

- Windows with PowerShell 5.1 or PowerShell 7+  
- Appropriate rights (local admin / domain admin depending on the script)  
- Network connectivity and firewall rules allowing the required remoting/RPC calls  
- SMTP access for scripts that send email notifications

## Disclaimer

These scripts are provided **as‑is**, with no warranty.  
Test everything in a lab or non‑production environment first.  
You are responsible for what you run on your systems.

## Contributing

Suggestions, issues and pull requests are welcome:

- Open an issue if something breaks or could be improved  
- Send a PR if you want to add a script or enhance an existing one

Geeky ideas and weird lab edge cases are highly appreciated.

## License

Unless otherwise noted in a specific file, all scripts in this repository are released under the **MIT License**.  
See the `LICENSE` file for the full text.
