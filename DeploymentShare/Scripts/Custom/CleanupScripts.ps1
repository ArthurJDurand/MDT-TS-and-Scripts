<#
.SYNOPSIS
    Removes MDT deployment-related scripts and folders post-deployment for clean system state.

.DESCRIPTION
    Automatically cleans up Microsoft Deployment Toolkit temporary files, task sequence data,
    and bootstrap scripts from Windows drive after deployment completion.

.NOTES
    - Targets standard MDT directories and files: _SMSTaskSequence, MININT, LTIBootstrap.vbs
    - Requires Windows drive with standard file system labeling
    - Safe for post-deployment automation
#>

# =========================================================
# MAIN EXECUTION
# =========================================================

# =========================================================
# PHASE 1: SYSTEM DETECTION
# =========================================================

# Get the Windows drive letter
$WindowsDriveLetter = (Get-Volume -FileSystemLabel Windows).DriveLetter

# =========================================================
# PHASE 2: CLEANUP TARGETS DEFINITION
# =========================================================

# Cleanup MDT deployment scripts if Windows drive is present
if ($WindowsDriveLetter) {
    $PathsToRemove = @(
        "$($WindowsDriveLetter):\_SMSTaskSequence",
        "$($WindowsDriveLetter):\MININT", 
        "$($WindowsDriveLetter):\LTIBootstrap.vbs"
    )

    # =========================================================
    # PHASE 3: CLEANUP EXECUTION
    # =========================================================

    foreach ($Path in $PathsToRemove) {
        if (Test-Path $Path) {
            Remove-Item $Path -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# =========================================================
# SCRIPT COMPLETION
# =========================================================
