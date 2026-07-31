Set-StrictMode -Version 2.0

if ($null -eq ('DriveAura.Native.ProcessSnapshot' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace DriveAura.Native {
    public sealed class ProcessEntry {
        public int ProcessId { get; set; }
        public int ParentProcessId { get; set; }
    }

    public static class ProcessSnapshot {
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private static readonly IntPtr InvalidHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PROCESSENTRY32 {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool Process32FirstW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool Process32NextW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        public static ProcessEntry[] Read() {
            IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == InvalidHandle) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            try {
                var rows = new List<ProcessEntry>();
                var entry = new PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                if (!Process32FirstW(snapshot, ref entry)) {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 18) {
                        return rows.ToArray();
                    }
                    throw new Win32Exception(error);
                }
                do {
                    rows.Add(new ProcessEntry {
                        ProcessId = unchecked((int)entry.th32ProcessID),
                        ParentProcessId = unchecked((int)entry.th32ParentProcessID)
                    });
                    entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                } while (Process32NextW(snapshot, ref entry));
                return rows.ToArray();
            } finally {
                CloseHandle(snapshot);
            }
        }
    }

    public sealed class BoundedProcessResult {
        public int ProcessId { get; set; }
        public int ExitCode { get; set; }
        public bool TimedOut { get; set; }
    }

    public static class BoundedProcess {
        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint CREATE_NO_WINDOW = 0x08000000;
        private const uint STARTF_USESTDHANDLES = 0x00000100;
        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint CREATE_ALWAYS = 2;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JobObjectExtendedLimitInformation = 9;
        private const uint WAIT_OBJECT_0 = 0;
        private const uint WAIT_TIMEOUT = 258;
        private static readonly IntPtr InvalidHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            public int bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int infoClass,
            IntPtr info,
            uint length
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            ref SECURITY_ATTRIBUTES securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile
        );

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(
            string applicationName,
            System.Text.StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            bool inheritHandles,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation
        );

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        private static void ThrowLastError(string operation) {
            throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
        }

        public static BoundedProcessResult Run(
            string applicationName,
            string commandLine,
            string workingDirectory,
            string standardOutputPath,
            string standardErrorPath,
            int timeoutMilliseconds
        ) {
            IntPtr job = IntPtr.Zero;
            IntPtr output = IntPtr.Zero;
            IntPtr error = IntPtr.Zero;
            IntPtr input = IntPtr.Zero;
            PROCESS_INFORMATION processInfo = new PROCESS_INFORMATION();
            bool processCreated = false;
            try {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) {
                    ThrowLastError("CreateJobObject");
                }

                var limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                limits.BasicLimitInformation.LimitFlags =
                    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                int limitsSize = Marshal.SizeOf(typeof(
                    JOBOBJECT_EXTENDED_LIMIT_INFORMATION
                ));
                IntPtr limitsPointer = Marshal.AllocHGlobal(limitsSize);
                try {
                    Marshal.StructureToPtr(limits, limitsPointer, false);
                    if (!SetInformationJobObject(
                            job,
                            JobObjectExtendedLimitInformation,
                            limitsPointer,
                            (uint)limitsSize
                        )) {
                        ThrowLastError("SetInformationJobObject");
                    }
                } finally {
                    Marshal.FreeHGlobal(limitsPointer);
                }

                var security = new SECURITY_ATTRIBUTES();
                security.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                security.bInheritHandle = 1;
                uint sharing = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
                output = CreateFile(
                    standardOutputPath,
                    GENERIC_WRITE,
                    sharing,
                    ref security,
                    CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL,
                    IntPtr.Zero
                );
                if (output == InvalidHandle) {
                    ThrowLastError("CreateFile stdout");
                }
                error = CreateFile(
                    standardErrorPath,
                    GENERIC_WRITE,
                    sharing,
                    ref security,
                    CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL,
                    IntPtr.Zero
                );
                if (error == InvalidHandle) {
                    ThrowLastError("CreateFile stderr");
                }
                input = CreateFile(
                    "NUL",
                    GENERIC_READ,
                    sharing,
                    ref security,
                    OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL,
                    IntPtr.Zero
                );
                if (input == InvalidHandle) {
                    ThrowLastError("CreateFile stdin");
                }

                var startup = new STARTUPINFO();
                startup.cb = Marshal.SizeOf(typeof(STARTUPINFO));
                startup.dwFlags = STARTF_USESTDHANDLES;
                startup.hStdInput = input;
                startup.hStdOutput = output;
                startup.hStdError = error;
                var mutableCommandLine = new System.Text.StringBuilder(commandLine);
                if (!CreateProcess(
                        applicationName,
                        mutableCommandLine,
                        IntPtr.Zero,
                        IntPtr.Zero,
                        true,
                        CREATE_SUSPENDED | CREATE_NO_WINDOW,
                        IntPtr.Zero,
                        workingDirectory,
                        ref startup,
                        out processInfo
                    )) {
                    ThrowLastError("CreateProcess");
                }
                processCreated = true;
                if (!AssignProcessToJobObject(job, processInfo.hProcess)) {
                    ThrowLastError("AssignProcessToJobObject");
                }
                if (ResumeThread(processInfo.hThread) == UInt32.MaxValue) {
                    ThrowLastError("ResumeThread");
                }

                uint wait = WaitForSingleObject(
                    processInfo.hProcess,
                    (uint)timeoutMilliseconds
                );
                if (wait == WAIT_TIMEOUT) {
                    CloseHandle(job);
                    job = IntPtr.Zero;
                    WaitForSingleObject(processInfo.hProcess, 5000);
                    return new BoundedProcessResult {
                        ProcessId = unchecked((int)processInfo.dwProcessId),
                        ExitCode = -1,
                        TimedOut = true
                    };
                }
                if (wait != WAIT_OBJECT_0) {
                    ThrowLastError("WaitForSingleObject");
                }
                uint exitCode;
                if (!GetExitCodeProcess(processInfo.hProcess, out exitCode)) {
                    ThrowLastError("GetExitCodeProcess");
                }
                return new BoundedProcessResult {
                    ProcessId = unchecked((int)processInfo.dwProcessId),
                    ExitCode = unchecked((int)exitCode),
                    TimedOut = false
                };
            } catch {
                if (processCreated && processInfo.hProcess != IntPtr.Zero) {
                    TerminateProcess(processInfo.hProcess, 1);
                }
                throw;
            } finally {
                if (job != IntPtr.Zero) {
                    CloseHandle(job);
                }
                if (processInfo.hThread != IntPtr.Zero) {
                    CloseHandle(processInfo.hThread);
                }
                if (processInfo.hProcess != IntPtr.Zero) {
                    CloseHandle(processInfo.hProcess);
                }
                if (input != IntPtr.Zero && input != InvalidHandle) {
                    CloseHandle(input);
                }
                if (error != IntPtr.Zero && error != InvalidHandle) {
                    CloseHandle(error);
                }
                if (output != IntPtr.Zero && output != InvalidHandle) {
                    CloseHandle(output);
                }
            }
        }
    }
}
'@
}

function Write-DriveAuraStep {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("[Drive Aura] {0}" -f $Message)
}

function Resolve-DriveAuraExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Label non trovato. Indicare il percorso esplicito."
    }
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $command = Get-Command $Value -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        throw "$Label non trovato: $Value"
    }
    return $command.Source
}

function ConvertTo-DriveAuraWindowsArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        $Value = ''
    }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"&|<>^()]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append([char]34)
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            for ($index = 0; $index -lt (($backslashes * 2) + 1); $index++) {
                [void]$builder.Append([char]92)
            }
            [void]$builder.Append([char]34)
            $backslashes = 0
            continue
        }
        for ($index = 0; $index -lt $backslashes; $index++) {
            [void]$builder.Append([char]92)
        }
        $backslashes = 0
        [void]$builder.Append($character)
    }
    for ($index = 0; $index -lt ($backslashes * 2); $index++) {
        [void]$builder.Append([char]92)
    }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function ConvertTo-DriveAuraProcessPath {
    param([Parameter(Mandatory = $true)][string]$Value)

    $path = $Value.Trim().Trim([char]34)
    if ($path.StartsWith('\??\', [StringComparison]::Ordinal)) {
        $path = $path.Substring(4)
    } elseif ($path.StartsWith('\\?\', [StringComparison]::Ordinal)) {
        $path = $path.Substring(4)
    } elseif ($path.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) {
        $path = Join-Path $env:SystemRoot $path.Substring(12)
    }
    try {
        return [IO.Path]::GetFullPath($path)
    } catch {
        throw "Percorso processo non valido: $path"
    }
}

function New-DriveAuraProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$CommandMarker,
        [string]$ExpectedExecutablePath
    )

    $Process.Refresh()
    $path = $null
    try {
        $path = $Process.MainModule.FileName
    } catch {
        $path = $ExpectedExecutablePath
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $ExpectedExecutablePath
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Percorso del processo PID $($Process.Id) non disponibile."
    }
    return [pscustomobject]@{
        pid = [int]$Process.Id
        executablePath = ConvertTo-DriveAuraProcessPath -Value $path
        # Windows PowerShell 5.1 may deserialize a JSON integer this large via
        # Double and lose low-order bits. Keep the process creation FILETIME
        # equivalent as decimal text so the PID-reuse check remains exact.
        startedUtcTicks = ([long]$Process.StartTime.ToUniversalTime().Ticks).ToString(
            [Globalization.CultureInfo]::InvariantCulture
        )
        commandMarker = $CommandMarker
    }
}

function Test-DriveAuraProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][psobject]$Identity,
        [string]$Label = 'processo'
    )

    $processId = [int]$Identity.pid
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $false
    }
    $actualPathValue = [string]$process.Path
    if ([string]::IsNullOrWhiteSpace($actualPathValue)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return $false
        }
        $actualPathValue = [string]$process.Path
        if ([string]::IsNullOrWhiteSpace($actualPathValue)) {
            throw "Rifiutato uso PID ${processId}: percorso $Label non disponibile."
        }
    }
    $actualPath = ConvertTo-DriveAuraProcessPath -Value $actualPathValue
    $expectedPath = ConvertTo-DriveAuraProcessPath -Value ([string]$Identity.executablePath)
    $actualTicks = [long]$process.StartTime.ToUniversalTime().Ticks
    $expectedTicks = [long]$Identity.startedUtcTicks
    if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("Rifiutato uso PID {0}: percorso {1} non coincidente." -f
            $processId, $Label)
    }
    if ($actualTicks -ne $expectedTicks) {
        throw ("Rifiutato uso PID {0}: istante di avvio {1} non coincidente." -f
            $processId, $Label)
    }
    return $true
}

function Stop-DriveAuraOwnedProcessTree {
    param(
        [Parameter(Mandatory = $true)][psobject]$Identity,
        [string]$Label = 'processo',
        [ValidateRange(1, 15)][int]$TimeoutSeconds = 5
    )

    if (-not (Test-DriveAuraProcessIdentity -Identity $Identity -Label $Label)) {
        return
    }

    $rootId = [int]$Identity.pid
    $rootTicks = [long]$Identity.startedUtcTicks
    $depthByPid = @{}
    $depthByPid[$rootId] = 0
    $snapshot = @([DriveAura.Native.ProcessSnapshot]::Read())
    for ($round = 0; $round -lt $snapshot.Count; $round++) {
        $changed = $false
        foreach ($row in $snapshot) {
            $processId = [int]$row.ProcessId
            $parentId = [int]$row.ParentProcessId
            if (-not $depthByPid.ContainsKey($processId) -and
                $depthByPid.ContainsKey($parentId)) {
                $depthByPid[$processId] = [int]$depthByPid[$parentId] + 1
                $changed = $true
            }
        }
        if (-not $changed) {
            break
        }
    }

    $owned = New-Object System.Collections.Generic.List[object]
    foreach ($processId in $depthByPid.Keys) {
        $process = Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }
        $startedTicks = [long]$process.StartTime.ToUniversalTime().Ticks
        if ([int]$processId -ne $rootId -and $startedTicks -lt $rootTicks) {
            throw "Rifiutato arresto PID ${processId}: discendente $Label con istante non valido."
        }
        $path = [string]$process.Path
        if ([string]::IsNullOrWhiteSpace($path)) {
            $process = Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue
            if ($null -eq $process) {
                continue
            }
            $path = [string]$process.Path
            if ([string]::IsNullOrWhiteSpace($path)) {
                Write-Warning (
                    "Discendente PID $processId non arrestato direttamente: " +
                    'percorso non disponibile; saranno verificati radice e porte.'
                )
                continue
            }
        }
        $entryIdentity = [pscustomobject]@{
            pid = [int]$processId
            executablePath = ConvertTo-DriveAuraProcessPath -Value $path
            startedUtcTicks = $startedTicks.ToString(
                [Globalization.CultureInfo]::InvariantCulture
            )
            commandMarker = if ([int]$processId -eq $rootId) {
                [string]$Identity.commandMarker
            } else {
                "discendente del PID $rootId"
            }
        }
        Test-DriveAuraProcessIdentity -Identity $entryIdentity -Label $Label | Out-Null
        $owned.Add([pscustomobject]@{
                Identity = $entryIdentity
                Depth = [int]$depthByPid[[int]$processId]
            })
    }

    foreach ($entry in @($owned | Sort-Object Depth -Descending)) {
        $entryIdentity = $entry.Identity
        if (Test-DriveAuraProcessIdentity -Identity $entryIdentity -Label $Label) {
            Stop-Process -Id ([int]$entryIdentity.pid) -Force -ErrorAction Stop
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $stillOwned = @(
            foreach ($entry in $owned) {
                try {
                    if (Test-DriveAuraProcessIdentity `
                            -Identity $entry.Identity -Label $Label) {
                        $entry.Identity
                    }
                } catch {
                    # Un PID riutilizzato non appartiene piu all'albero arrestato.
                }
            }
        )
        if ($stillOwned.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Albero $Label ancora attivo dopo $TimeoutSeconds secondi."
}

function Start-DriveAuraManagedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$WrapperPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $wrapper = (Resolve-Path -LiteralPath $WrapperPath -ErrorAction Stop).Path
    $working = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).Path
    if ($wrapper.Contains('%')) {
        throw (
            "Percorso script non supportato: il carattere % verrebbe espanso da cmd.exe. " +
            'Usare una directory senza %.'
        )
    }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /q /v:off /s /c "' +
        (ConvertTo-DriveAuraWindowsArgument -Value $wrapper) + '"'
    $startInfo.WorkingDirectory = $working
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Avvio del processo gestito non riuscito: $wrapper"
        }
        return New-DriveAuraProcessIdentity -Process $process -CommandMarker $wrapper `
            -ExpectedExecutablePath $env:ComSpec
    } finally {
        $process.Dispose()
    }
}

function Invoke-DriveAuraExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
    )

    $resolved = Resolve-DriveAuraExecutable -Value $FilePath -Label 'Comando esterno'
    $commandArguments = @(
        foreach ($argument in $Arguments) {
            ConvertTo-DriveAuraWindowsArgument -Value ([string]$argument)
        }
    ) -join ' '
    $extension = [IO.Path]::GetExtension($resolved)
    if ($extension -ieq '.bat' -or $extension -ieq '.cmd') {
        if ($resolved.Contains('%')) {
            throw (
                "Percorso script non supportato: il carattere % verrebbe espanso da cmd.exe. " +
                'Usare una directory senza %.'
            )
        }
        $batchLine = ConvertTo-DriveAuraWindowsArgument -Value $resolved
        if (-not [string]::IsNullOrWhiteSpace($commandArguments)) {
            $batchLine += ' ' + $commandArguments
        }
        $application = $env:ComSpec
        $nativeArguments = '/d /v:off /s /c "' + $batchLine + '"'
    } else {
        $application = $resolved
        $nativeArguments = $commandArguments
    }
    $commandLine = ConvertTo-DriveAuraWindowsArgument -Value $application
    if (-not [string]::IsNullOrWhiteSpace($nativeArguments)) {
        $commandLine += ' ' + $nativeArguments
    }
    $temporaryStem = Join-Path ([IO.Path]::GetTempPath()) (
        'drive-aura-external-' + [guid]::NewGuid().ToString('N')
    )
    $stdoutPath = $temporaryStem + '.out'
    $stderrPath = $temporaryStem + '.err'
    $nativeResult = $null
    $stdout = ''
    $stderr = ''
    try {
        $nativeResult = [DriveAura.Native.BoundedProcess]::Run(
            $application,
            $commandLine,
            (Get-Location).Path,
            $stdoutPath,
            $stderrPath,
            $TimeoutSeconds * 1000
        )
        if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
            $stdout = [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::Default)
        }
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            $stderr = [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::Default)
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        $parts += $stdout.TrimEnd("`r", "`n")
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $parts += $stderr.TrimEnd("`r", "`n")
    }
    $output = $parts -join [Environment]::NewLine
    if ($nativeResult.TimedOut) {
        throw ("Timeout di {0} secondi per il comando esterno {1}: {2}" -f
            $TimeoutSeconds, [IO.Path]::GetFileName($resolved), $output)
    }
    $exitCode = [int]$nativeResult.ExitCode
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw ("Comando non riuscito ({0}): {1}" -f $exitCode, $output)
    }
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = $output
    }
}

function Get-DriveAuraPythonRuntime {
    param([string]$PythonPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
        $candidates += [pscustomobject]@{ Value = $PythonPath; Prefix = @() }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:DRIVE_AURA_PYTHON)) {
        $candidates += [pscustomobject]@{ Value = $env:DRIVE_AURA_PYTHON; Prefix = @() }
    } else {
        $candidates += [pscustomobject]@{ Value = 'py'; Prefix = @('-3.12') }
        $candidates += [pscustomobject]@{ Value = 'python'; Prefix = @() }
    }

    $errors = @()
    foreach ($candidate in $candidates) {
        try {
            $executable = Resolve-DriveAuraExecutable -Value $candidate.Value -Label 'Python 3.12'
            $prefix = @($candidate.Prefix)
            if ([IO.Path]::GetFileNameWithoutExtension($executable) -ieq 'py' -and $prefix.Count -eq 0) {
                $prefix = @('-3.12')
            }
            $probe = Invoke-DriveAuraExternal -FilePath $executable -Arguments (
                $prefix + @(
                    '-c',
                    'import struct,sys; print(chr(46).join(map(str,sys.version_info[:3]))+chr(124)+str(struct.calcsize(chr(80))*8))'
                )
            )
            $match = [regex]::Match($probe.Output, '(?m)^(3\.\d+\.\d+)\|(32|64)\s*$')
            if (-not $match.Success) {
                throw 'versione non interpretabile'
            }
            $version = [version]$match.Groups[1].Value
            if ($version.Major -ne 3 -or $version.Minor -ne 12) {
                throw ("versione {0} incompatibile; e richiesto Python 3.12 x64" -f $version)
            }
            if ($match.Groups[2].Value -ne '64') {
                throw 'architettura a 32 bit incompatibile; e richiesto Python 3.12 x64'
            }
            $modules = Invoke-DriveAuraExternal -FilePath $executable -Arguments (
                $prefix + @('-c', 'import ensurepip,venv')
            ) -AllowFailure
            if ($modules.ExitCode -ne 0) {
                throw 'il runtime non include venv/ensurepip; installare la distribuzione completa di Python 3.12'
            }
            return [pscustomobject]@{
                Path = $executable
                PrefixArguments = @($prefix)
                Version = $version.ToString()
                Architecture = 'x64'
            }
        } catch {
            $errors += $_.Exception.Message
        }
    }
    throw ("Python 3.12 x64 compatibile non trovato. {0}" -f ($errors -join ' | '))
}

function Get-DriveAuraJavaRuntime {
    param([string]$JavaHome)

    if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
        $javaPath = Join-Path $JavaHome 'bin\java.exe'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $javaPath = Join-Path $env:JAVA_HOME 'bin\java.exe'
    } else {
        $javaPath = 'java'
    }
    $java = Resolve-DriveAuraExecutable -Value $javaPath -Label 'Java'
    $probe = Invoke-DriveAuraExternal -FilePath $java -Arguments @(
        '-XshowSettings:properties',
        '-version'
    )
    $versionMatch = [regex]::Match($probe.Output, '(?m)^\s*java\.version\s*=\s*([^\s]+)\s*$')
    $homeMatch = [regex]::Match($probe.Output, '(?m)^\s*java\.home\s*=\s*(.+?)\s*$')
    if (-not $versionMatch.Success -or -not $homeMatch.Success) {
        throw 'Versione o directory Java non riconosciuta.'
    }
    $versionText = $versionMatch.Groups[1].Value
    if ($versionText -match '^1\.(\d+)') {
        $major = [int]$Matches[1]
    } elseif ($versionText -match '^(\d+)') {
        $major = [int]$Matches[1]
    } else {
        throw "Versione Java non riconosciuta: $versionText"
    }
    if ($major -lt 8) {
        throw "Java $versionText incompatibile; e richiesto Java 8 o successivo."
    }
    $home = $homeMatch.Groups[1].Value.Trim()
    if (-not (Test-Path -LiteralPath $home -PathType Container)) {
        throw "Directory Java non valida: $home"
    }
    return [pscustomobject]@{
        Path = $java
        Home = (Resolve-Path -LiteralPath $home).Path
        Version = $versionText
        Major = $major
    }
}

function Assert-DriveAuraJavaTomcatCompatibility {
    param(
        [Parameter(Mandatory = $true)][int]$JavaMajor,
        [Parameter(Mandatory = $true)][int]$TomcatMajor
    )

    if ($TomcatMajor -eq 9 -and $JavaMajor -lt 8) {
        throw 'Tomcat 9 richiede Java 8 o successivo.'
    }
    if ($TomcatMajor -eq 11 -and $JavaMajor -lt 17) {
        throw 'Tomcat 11 richiede Java 17 o successivo.'
    }
    if ($TomcatMajor -ne 9 -and $TomcatMajor -ne 11) {
        throw "Tomcat $TomcatMajor non supportato: usare Tomcat 9 oppure Tomcat 11."
    }
}

function Get-DriveAuraTomcatRuntime {
    param(
        [string]$TomcatHome,
        [Parameter(Mandatory = $true)][psobject]$JavaRuntime
    )

    if ([string]::IsNullOrWhiteSpace($TomcatHome)) {
        $TomcatHome = $env:CATALINA_HOME
    }
    if ([string]::IsNullOrWhiteSpace($TomcatHome) -or
        -not (Test-Path -LiteralPath $TomcatHome -PathType Container)) {
        throw 'Tomcat non trovato. Indicare -TomcatHome oppure CATALINA_HOME.'
    }
    $home = (Resolve-Path -LiteralPath $TomcatHome).Path
    foreach ($relative in @('bin\catalina.bat', 'bin\version.bat', 'lib\catalina.jar', 'conf\server.xml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $home $relative) -PathType Leaf)) {
            throw "Tomcat non riconosciuto: manca $relative."
        }
    }

    $oldJavaHome = $env:JAVA_HOME
    $oldJreHome = $env:JRE_HOME
    $oldCatalinaHome = $env:CATALINA_HOME
    try {
        $env:JAVA_HOME = $JavaRuntime.Home
        $env:JRE_HOME = $JavaRuntime.Home
        $env:CATALINA_HOME = $home
        $probe = Invoke-DriveAuraExternal -FilePath (Join-Path $home 'bin\version.bat')
    } finally {
        $env:JAVA_HOME = $oldJavaHome
        $env:JRE_HOME = $oldJreHome
        $env:CATALINA_HOME = $oldCatalinaHome
    }
    $match = [regex]::Match($probe.Output, 'Server version:\s*Apache Tomcat/(\d+)\.([0-9.]+)')
    if (-not $match.Success) {
        throw 'Versione Tomcat non riconosciuta dal comando bin\version.bat.'
    }
    $major = [int]$match.Groups[1].Value
    Assert-DriveAuraJavaTomcatCompatibility -JavaMajor $JavaRuntime.Major -TomcatMajor $major
    return [pscustomobject]@{
        Home = $home
        Version = ("{0}.{1}" -f $match.Groups[1].Value, $match.Groups[2].Value)
        Major = $major
    }
}

function Assert-DriveAuraPostgresVersionCompatibility {
    param([Parameter(Mandatory = $true)][int]$Major)
    if ($Major -lt 14 -or $Major -gt 18) {
        throw "PostgreSQL $Major incompatibile; sono ammesse le versioni da 14 a 18."
    }
}

function Get-DriveAuraPostgresRuntime {
    param([string]$PostgresBin)

    if ([string]::IsNullOrWhiteSpace($PostgresBin)) {
        $PostgresBin = $env:POSTGRES_BIN
    }
    if ([string]::IsNullOrWhiteSpace($PostgresBin)) {
        $psql = Get-Command 'psql.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $psql) {
            $PostgresBin = Split-Path -Parent $psql.Source
        }
    }
    if ([string]::IsNullOrWhiteSpace($PostgresBin) -or
        -not (Test-Path -LiteralPath $PostgresBin -PathType Container)) {
        throw 'PostgreSQL non trovato. Indicare -PostgresBin oppure POSTGRES_BIN.'
    }
    $bin = (Resolve-Path -LiteralPath $PostgresBin).Path
    foreach ($name in @('psql.exe', 'pg_isready.exe', 'createdb.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bin $name) -PathType Leaf)) {
            throw "PostgreSQL non riconosciuto: manca $name."
        }
    }
    $probe = Invoke-DriveAuraExternal -FilePath (Join-Path $bin 'psql.exe') -Arguments @('--version')
    $match = [regex]::Match($probe.Output, 'PostgreSQL\)\s+(\d+)(?:\.([0-9]+))?')
    if (-not $match.Success) {
        throw 'Versione PostgreSQL non riconosciuta.'
    }
    $major = [int]$match.Groups[1].Value
    Assert-DriveAuraPostgresVersionCompatibility -Major $major
    return [pscustomobject]@{
        Bin = $bin
        Version = if ($match.Groups[2].Success) {
            "$major.$($match.Groups[2].Value)"
        } else {
            "$major"
        }
        Major = $major
    }
}

function Assert-DriveAuraIdentifier {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "$Label non valido. Usare soltanto lettere, numeri e underscore."
    }
}

function Assert-DriveAuraSecrets {
    param([string[]]$Names = @(
        'POSTGRES_PASSWORD',
        'DJANGO_SECRET_KEY',
        'LOCAL_API_SECRET',
        'REMOTE_API_SECRET',
        'BRIDGE_API_SECRET'
    ))

    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Segreto mancante: impostare `$env:$name nella sessione corrente."
        }
        if ($value.Length -lt 12) {
            throw "Segreto $name troppo corto: usare almeno 12 caratteri."
        }
    }
}

function Assert-DriveAuraPortAvailable {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [string]$Label = 'Porta'
    )
    if ($Port -lt 1024 -or $Port -gt 65535) {
        throw "$Label non valida: $Port."
    }
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
    } catch {
        throw "$Label $Port occupata. Scegliere una porta libera senza terminare processi estranei."
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Assert-DriveAuraRemoteUrl {
    param([Parameter(Mandatory = $true)][string]$Value)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw 'RemoteApiUrl deve essere un URL HTTP o HTTPS assoluto senza credenziali, query o frammento.'
    }
    if ($uri.Scheme -eq 'http' -and -not $uri.IsLoopback) {
        throw 'RemoteApiUrl richiede HTTPS; HTTP e ammesso soltanto su loopback.'
    }
    return $uri
}

function Wait-DriveAuraHealth {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ExpectedService,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
        [psobject]$ProcessIdentity,
        [string]$ProcessLabel = 'servizio'
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($null -ne $ProcessIdentity -and
            -not (Test-DriveAuraProcessIdentity -Identity $ProcessIdentity -Label $ProcessLabel)) {
            throw "$ProcessLabel terminato prima della readiness $ExpectedService."
        }
        try {
            $remaining = [Math]::Max(
                1,
                [Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalSeconds)
            )
            $requestTimeout = [Math]::Min(3, [int]$remaining)
            $response = Invoke-RestMethod -Method Get `
                -Uri ($BaseUrl.TrimEnd('/') + '/health') -TimeoutSec $requestTimeout
            if ($response.apiVersion -eq '1.0' -and
                $response.service -eq $ExpectedService -and
                $response.status -eq 'ok') {
                return
            }
            $lastError = 'contratto inatteso'
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Readiness $ExpectedService non raggiunta entro $TimeoutSeconds secondi: $lastError"
}

function Test-DriveAuraWheelhouse {
    param([Parameter(Mandatory = $true)][string]$Wheelhouse)

    $root = (Resolve-Path -LiteralPath $Wheelhouse -ErrorAction Stop).Path
    $checksumPath = Join-Path $root 'SHA256SUMS.txt'
    $requirementsPath = Join-Path $root 'requirements-offline.txt'
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
        throw 'Wheelhouse incompleta: mancano SHA256SUMS.txt o requirements-offline.txt.'
    }
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $checksumPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9_.+-]+\.whl)$') {
            throw "Riga checksum wheel non valida: $line"
        }
        $key = $Matches[2].ToLowerInvariant()
        if ($expected.ContainsKey($key)) {
            throw "Wheel duplicata nel manifest: $($Matches[2])"
        }
        $expected[$key] = $Matches[1]
    }
    $actual = @(Get-ChildItem -LiteralPath $root -File -Filter '*.whl')
    if ($actual.Count -eq 0 -or $actual.Count -ne $expected.Count) {
        throw 'Numero di wheel diverso dal manifest.'
    }
    foreach ($file in $actual) {
        $key = $file.Name.ToLowerInvariant()
        if (-not $expected.ContainsKey($key)) {
            throw "Wheel non dichiarata: $($file.Name)"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        if ($hash -ne $expected[$key]) {
            throw "Checksum wheel non valido: $($file.Name)"
        }
    }
    $requiredNames = @('django-', 'psycopg-', 'psycopg_binary-', 'asgiref-', 'sqlparse-', 'tzdata-')
    foreach ($prefix in $requiredNames) {
        if (-not @($actual | Where-Object { $_.Name.ToLowerInvariant().StartsWith($prefix) })) {
            throw "Wheel obbligatoria mancante: $prefix"
        }
    }
    return [pscustomobject]@{
        Root = $root
        Requirements = $requirementsPath
        Count = $actual.Count
    }
}

function Invoke-DriveAuraPostgresExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_PASSWORD)) {
        throw 'Segreto mancante: impostare $env:POSTGRES_PASSWORD.'
    }
    $previousPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $env:POSTGRES_PASSWORD
        return Invoke-DriveAuraExternal -FilePath $FilePath -Arguments $Arguments `
            -AllowFailure:$AllowFailure
    } finally {
        $env:PGPASSWORD = $previousPassword
    }
}

function Test-DriveAuraPostgresReady {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [string]$Database = 'postgres'
    )

    Assert-DriveAuraIdentifier -Value $User -Label 'Utente PostgreSQL'
    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_PASSWORD)) {
        throw 'Segreto mancante: impostare $env:POSTGRES_PASSWORD.'
    }
    $ready = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'pg_isready.exe') `
        -Arguments @('--host', $HostName, '--port', "$Port", '--username', $User, '--dbname', $Database) `
        -AllowFailure
    if ($ready.ExitCode -ne 0) {
        throw "PostgreSQL non raggiungibile su ${HostName}:$Port. Verificare servizio, porta e firewall."
    }
    $query = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', 'SELECT 1'
        ) -AllowFailure
    if ($query.ExitCode -ne 0 -or $query.Output.Trim() -ne '1') {
        throw 'Autenticazione PostgreSQL fallita. Verificare utente, password e pg_hba.conf.'
    }
    $serverVersion = Invoke-DriveAuraPostgresExternal `
        -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', 'SHOW server_version_num'
        ) -AllowFailure
    $serverVersionNumber = 0
    if ($serverVersion.ExitCode -ne 0 -or
        -not [int]::TryParse($serverVersion.Output.Trim(), [ref]$serverVersionNumber)) {
        throw 'Versione del server PostgreSQL non interpretabile.'
    }
    $serverMajor = [int][Math]::Floor($serverVersionNumber / 10000)
    Assert-DriveAuraPostgresVersionCompatibility -Major $serverMajor
}

function Test-DriveAuraDatabaseExists {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    $sql = "SELECT 1 FROM pg_database WHERE datname = '$Database'"
    $result = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', 'postgres',
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', $sql
        )
    return $result.Output.Trim() -eq '1'
}

function New-DriveAuraDatabase {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'createdb.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--no-password',
            '--encoding', 'UTF8',
            '--template', 'template0',
            $Database
        ) | Out-Null
}

function Get-DriveAuraDomainRowCount {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    $sql = @'
SELECT
  (SELECT COUNT(*) FROM cittadino) +
  (SELECT COUNT(*) FROM patologia) +
  (SELECT COUNT(*) FROM patologia_cronica) +
  (SELECT COUNT(*) FROM patologia_mortale) +
  (SELECT COUNT(*) FROM ospedale) +
  (SELECT COUNT(*) FROM ricovero) +
  (SELECT COUNT(*) FROM patologia_ricovero) +
  (SELECT COUNT(*) FROM progressivo_ricovero);
'@
    $result = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', $sql
        )
    $value = 0L
    if (-not [long]::TryParse($result.Output.Trim(), [ref]$value)) {
        throw 'Conteggio delle tabelle PostgreSQL non interpretabile.'
    }
    return $value
}

function Save-DriveAuraState {
    param(
        [Parameter(Mandatory = $true)][psobject]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DriveAuraState {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configurazione installata non trovata: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Set-DriveAuraProcessEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Values)
    $previous = @{}
    foreach ($name in $Values.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$Values[$name], 'Process')
    }
    return $previous
}

function Restore-DriveAuraProcessEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Previous)
    foreach ($name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Previous[$name], 'Process')
    }
}

function Repair-DriveAuraPathEnvironment {
    $environment = [Environment]::GetEnvironmentVariables('Process')
    $pathNames = @(
        $environment.Keys |
            Where-Object {
                [string]::Equals(
                    [string]$_,
                    'Path',
                    [StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object {
                if ([string]$_ -ceq 'Path') { 0 } else { 1 }
            }, {
                [string]$_
            }
    )
    if ($pathNames.Count -le 1) {
        return $false
    }

    # Windows accepts duplicate environment names that differ only by case, but
    # Windows PowerShell Start-Process rejects that environment block. Preserve
    # every distinct path segment while reducing the aliases to one canonical key.
    $segments = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' (
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($name in $pathNames) {
        foreach ($segment in ([string]$environment[$name] -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($segment) -and $seen.Add($segment)) {
                $segments.Add($segment)
            }
        }
    }
    foreach ($name in $pathNames) {
        [Environment]::SetEnvironmentVariable([string]$name, $null, 'Process')
    }
    [Environment]::SetEnvironmentVariable('Path', ($segments -join ';'), 'Process')
    return $true
}

function Get-DriveAuraProcessCommandLine {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try {
        $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" `
            -OperationTimeoutSec 3 -ErrorAction Stop
        return [string]$process.CommandLine
    } catch {
        return ''
    }
}

Export-ModuleMember -Function @(
    'Write-DriveAuraStep',
    'Resolve-DriveAuraExecutable',
    'Invoke-DriveAuraExternal',
    'New-DriveAuraProcessIdentity',
    'Test-DriveAuraProcessIdentity',
    'Stop-DriveAuraOwnedProcessTree',
    'Start-DriveAuraManagedProcess',
    'Get-DriveAuraPythonRuntime',
    'Get-DriveAuraJavaRuntime',
    'Assert-DriveAuraJavaTomcatCompatibility',
    'Get-DriveAuraTomcatRuntime',
    'Get-DriveAuraPostgresRuntime',
    'Assert-DriveAuraPostgresVersionCompatibility',
    'Assert-DriveAuraIdentifier',
    'Assert-DriveAuraSecrets',
    'Assert-DriveAuraPortAvailable',
    'Assert-DriveAuraRemoteUrl',
    'Wait-DriveAuraHealth',
    'Test-DriveAuraWheelhouse',
    'Test-DriveAuraPostgresReady',
    'Test-DriveAuraDatabaseExists',
    'New-DriveAuraDatabase',
    'Get-DriveAuraDomainRowCount',
    'Save-DriveAuraState',
    'Get-DriveAuraState',
    'Set-DriveAuraProcessEnvironment',
    'Restore-DriveAuraProcessEnvironment',
    'Repair-DriveAuraPathEnvironment',
    'Get-DriveAuraProcessCommandLine'
)
