<#
.SYNOPSIS
  Submits URLs to IndexNow (Bing, Yandex, Seznam, Naver, Yep).

.DESCRIPTION
  IndexNow is the only real "push to index" API available for a static site.
  Bing's index also grounds ChatGPT's web search, so this doubles as an AEO action.

  Google does NOT participate in IndexNow, and its Indexing API only supports
  JobPosting / BroadcastEvent — see .claude/agents/seo-aeo-blog.md, Phase 5.

  PREREQUISITE: the key file must be reachable in production at
    https://www.meeting-ai-analyser.com/<key>.txt
  and contain the key as its only line. A 403 response means it isn't.
  Submitting a page that isn't deployed yet will fail validation.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/indexnow.ps1 -Urls "https://www.meeting-ai-analyser.com/blog.html"

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/indexnow.ps1 -Urls "https://www.meeting-ai-analyser.com/blog.html" -WhatIf

.NOTES
  -ExecutionPolicy Bypass is required: script execution is disabled by default on this machine.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string[]] $Urls,

    [string] $Host_ = 'www.meeting-ai-analyser.com',

    [string] $Key = '607bac788ac14fc09b9037b3ea094752fcd6afeddd3a4aed8fff1292b42723d6',

    [string] $Endpoint = 'https://api.indexnow.org/indexnow'
)

$ErrorActionPreference = 'Stop'

$keyLocation = "https://$Host_/$Key.txt"

# IndexNow rejects URLs that don't belong to the declared host.
$bad = $Urls | Where-Object { $_ -notmatch "^https?://$([regex]::Escape($Host_))/" }
if ($bad) {
    throw "These URLs don't match host '$Host_': $($bad -join ', ')"
}

$body = [ordered]@{
    host        = $Host_
    key         = $Key
    keyLocation = $keyLocation
    urlList     = @($Urls)
} | ConvertTo-Json -Depth 3

Write-Host "IndexNow -> $Endpoint"
Write-Host "  host:        $Host_"
Write-Host "  keyLocation: $keyLocation"
Write-Host "  urls:"
$Urls | ForEach-Object { Write-Host "    - $_" }

# Verify the key file is actually served before submitting; a missing key is the
# single most common cause of a silent 403.
try {
    $keyCheck = Invoke-WebRequest -Uri $keyLocation -UseBasicParsing -TimeoutSec 15
    if ($keyCheck.Content.Trim() -ne $Key) {
        Write-Warning "Key file at $keyLocation does not contain the expected key. Submission will likely be rejected."
    }
    else {
        Write-Host "Key file verified." -ForegroundColor Green
    }
}
catch {
    Write-Warning "Could not fetch $keyLocation ($($_.Exception.Message)). Deploy $Key.txt to the site root first."
}

if (-not $PSCmdlet.ShouldProcess(($Urls -join ', '), 'Submit to IndexNow')) {
    Write-Host "`n-WhatIf: nothing submitted. Payload would be:`n$body"
    return
}

try {
    $response = Invoke-WebRequest -Uri $Endpoint -Method Post -Body $body `
        -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 30

    Write-Host "`nHTTP $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
    Write-Host "Accepted. Crawling is queued, not immediate."
    exit 0
}
catch {
    $status = $null
    if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
        $status = [int] $_.Exception.Response.StatusCode
    }

    Write-Host "`nSubmission failed$(if ($status) { " (HTTP $status)" })" -ForegroundColor Red
    switch ($status) {
        400 { Write-Host 'Bad request: malformed URL list or JSON.' }
        403 { Write-Host "Forbidden: key not valid. Ensure $keyLocation is deployed and readable." }
        422 { Write-Host 'Unprocessable: URLs do not belong to the host, or the key does not match.' }
        429 { Write-Host 'Rate limited: too many submissions. Retry later, and batch URLs.' }
        default { Write-Host $_.Exception.Message }
    }
    exit 1
}
