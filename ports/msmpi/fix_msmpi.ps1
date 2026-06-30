<#
.SYNOPSIS
    Fix MSMPI executables that crash with STATUS_CRITICAL_INITIALIZATION_FAILURE
    on Windows 11 25H2+ due to CFG (Control Flow Guard) incompatibility.

.DESCRIPTION
    MSMPI v10.1.12498 (built 2019) has IMAGE_DLLCHARACTERISTICS_GUARD_CF (0x4000)
    set in its PE header. On Windows 11 25H2 (build 26200+), this causes ALL MSMPI 
    executables to crash with 0xC0000409 (STATUS_CRITICAL_INITIALIZATION_FAILURE)
    during process initialization.

    This script patches the PE header to clear the CFG flag, restoring functionality.
    It preserves all other PE characteristics (CET, ASLR, NX, etc.).

    Affected files:
      - C:\Program Files\Microsoft MPI\Bin\mpiexec.exe
      - C:\Program Files\Microsoft MPI\Bin\smpd.exe
      - C:\Program Files\Microsoft MPI\Bin\msmpilaunchsvc.exe
#>

$ErrorActionPreference = "Stop"
$files = @(
    "C:/Program Files/Microsoft MPI/Bin/mpiexec.exe",
    "C:/Program Files/Microsoft MPI/Bin/smpd.exe",
    "C:/Program Files/Microsoft MPI/Bin/msmpilaunchsvc.exe"
)

$fixed = 0
foreach ($file in $files) {
    if (-not (Test-Path $file)) {
        Write-Host ("[SKIP] Not found: " + $file)
        continue
    }
    
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $e_lfanew = [BitConverter]::ToUInt32($bytes, 0x3C)
    $peSig = [System.Text.Encoding]::ASCII.GetString($bytes, $e_lfanew, 4)
    if ($peSig -ne "PE`0`0") {
        Write-Host ("[SKIP] Invalid PE: " + $file)
        continue
    }
    
    # DLL Characteristics at IMAGE_OPTIONAL_HEADER64 offset 0x46
    $dllCharOffset = $e_lfanew + 4 + 20 + 0x46
    $dllChar = [BitConverter]::ToUInt16($bytes, $dllCharOffset)
    
    if (($dllChar -band 0x4000) -eq 0) {
        Write-Host ("[OK  ] CFG already cleared: " + $file)
        continue
    }
    
    $newDllChar = $dllChar -band (-bnot 0x4000)
    [BitConverter]::GetBytes($newDllChar) | ForEach-Object -Begin {$i=0} -Process {$bytes[$dllCharOffset+$i]=$_;$i++}
    [System.IO.File]::WriteAllBytes($file, $bytes)
    
    # Verify
    $verify = [BitConverter]::ToUInt16([System.IO.File]::ReadAllBytes($file), $dllCharOffset)
    Write-Host ("[FIX ] " + (Split-Path $file -Leaf) + ": 0x" + $dllChar.ToString("X4") + " -> 0x" + $verify.ToString("X4"))
    $fixed++
}

Write-Host ("`nFixed " + $fixed + " file(s).")

# Quick validation
Write-Host "`n=== Validation ==="
$testFile = "C:/Program Files/Microsoft MPI/Bin/mpiexec.exe"
$p = Start-Process -FilePath $testFile -ArgumentList "-?" -NoNewWindow -Wait -RedirectStandardOutput "$env:TEMP\mpi_verify.txt" -RedirectStandardError "$env:TEMP\mpi_verify_err.txt" -PassThru
$out = Get-Content "$env:TEMP\mpi_verify.txt" -ErrorAction SilentlyContinue -First 1
Write-Host ("mpiexec -? exit: " + $p.ExitCode + "  output: " + $out)
Remove-Item "$env:TEMP\mpi_verify.txt","$env:TEMP\mpi_verify_err.txt" -ErrorAction SilentlyContinue
