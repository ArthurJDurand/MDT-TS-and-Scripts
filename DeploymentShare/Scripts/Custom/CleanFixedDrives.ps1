<#
.SYNOPSIS
    Securely cleans all fixed drives by removing data and OEM partitions, excluding USB drives.

.DESCRIPTION
    Automatically detects and cleans all non-USB fixed drives, removing all data partitions
    and OEM configurations without user confirmation prompts.

.NOTES
    - Targets all fixed drives (non-USB) for complete data removal
    - Removes both data partitions and OEM-specific partitions
    - Runs without confirmation prompts for automated execution
    - Requires administrative privileges for disk operations
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: FIXED DRIVE DETECTION
# =========================================================

# Clean all non USB drives
Get-Disk | Where-Object { $_.Bustype -Ne "USB" } | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false

# =========================================================
# SCRIPT COMPLETION
# =========================================================
