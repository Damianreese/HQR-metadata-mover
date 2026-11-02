<#
  Metadata Mover - local server.
  Wraps the Salesforce CLI (sf) and serves the UI at http://localhost:<port>/
  Start it with Start-MetadataMover.cmd, or:
    powershell -NoProfile -ExecutionPolicy Bypass -File server.ps1 [-Port 8765] [-NoBrowser]
#>
param([int]$Port = 8765, [switch]$NoBrowser)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = $PSScriptRoot
$PkgRoot = Join-Path $Root 'packages'
$WorkDir = Join-Path $Root '.sf-workspace'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
# Random per-run token: the page gets it embedded, so other websites can't call this API.
$Token = [guid]::NewGuid().ToString('N')
$script:Sessions = @{}
$script:Running = $true
$script:StartedAt = Get-Date

$env:SF_AUTOUPDATE_DISABLE = 'true'
$env:SF_USE_PROGRESS_BAR = 'false'
$env:FORCE_COLOR = '0'

# sf commands run from a minimal project folder so every command works regardless of version.
$null = New-Item -ItemType Directory -Force -Path $PkgRoot, (Join-Path $WorkDir 'force-app')
$projFile = Join-Path $WorkDir 'sfdx-project.json'
if (-not (Test-Path $projFile)) {
  [IO.File]::WriteAllText($projFile, '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"60.0"}', $Utf8)
}

function Write-Log([string]$Msg, [string]$Color = 'Gray') {
  Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg) -ForegroundColor $Color
}

function Find-Sf {
  $c = Get-Command sf.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $candidates = @(
    "$env:ProgramFiles\sf\bin\sf.cmd",
    "${env:ProgramFiles(x86)}\sf\bin\sf.cmd",
    "$env:LOCALAPPDATA\sf\bin\sf.cmd",
    "$env:APPDATA\npm\sf.cmd"
  )
  foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
  return $null
}
$SfPath = Find-Sf

# ---------- process + http helpers ----------

function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -match '[\s"&|<>^()%!,;=]') { return '"' + ($a -replace '"', '\"') + '"' }
  return $a
}

function Invoke-Sf([string[]]$SfArgs, [int]$TimeoutSec = 1800) {
  if (-not $SfPath) { throw 'Salesforce CLI (sf) was not found. Install it, then restart Metadata Mover.' }
  $argText = ($SfArgs | ForEach-Object { Quote-Arg $_ }) -join ' '
  Write-Log "sf $argText" 'Cyan'
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  # cmd /s /c "..." keeps the quoting of a .cmd path with spaces intact.
  $psi.FileName = $env:ComSpec
  $psi.Arguments = '/d /s /c "' + '"' + $SfPath + '" ' + $argText + '"'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $WorkDir
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill() } catch {}
    throw "sf did not finish within $TimeoutSec seconds."
  }
  $p.WaitForExit()
  [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $out.Result; Err = $err.Result }
}

function ConvertFrom-SfJson([string]$Text) {
  $i = $Text.IndexOf('{')
  if ($i -lt 0) { throw "Unexpected output from sf: $Text" }
  $Text.Substring($i) | ConvertFrom-Json
}

function Invoke-Http([string]$Method, [string]$Url, [hashtable]$Headers, [string]$Body, [string]$ContentType) {
  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.Method = $Method
  $req.Timeout = 300000
  $req.ReadWriteTimeout = 300000
  $req.Accept = '*/*'
  if ($Headers) { foreach ($k in $Headers.Keys) { $req.Headers[$k] = $Headers[$k] } }
  if ($Body) {
    $bytes = $Utf8.GetBytes($Body)
    $req.ContentType = $ContentType
    $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
  }
  try { $resp = $req.GetResponse() }
  catch {
    $ex = $_.Exception
    while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
    if ($ex -and $ex.Response) { $resp = $ex.Response } else { throw }
  }
  $sr = New-Object IO.StreamReader($resp.GetResponseStream(), $Utf8)
  $text = $sr.ReadToEnd(); $sr.Close()
  $status = [int]$resp.StatusCode
  $resp.Close()
  @{ Status = $status; Body = $text }
}

function Get-OrgSession([string]$Org, [switch]$Refresh) {
  if (-not $Refresh -and $script:Sessions.ContainsKey($Org)) { return $script:Sessions[$Org] }
  $r = Invoke-Sf @('org', 'display', '--target-org', $Org, '--json') 120
  $j = ConvertFrom-SfJson $r.Out
  if (-not $j.result -or -not $j.result.instanceUrl) {
    throw ("Could not open a session for {0}: {1}. Try reconnecting the org." -f $Org, $j.message)
  }
  # Newer CLI versions redact the token in 'org display'; 'org auth show-access-token' returns it (and refreshes it first).
  $token = [string]$j.result.accessToken
  $t = Invoke-Sf @('org', 'auth', 'show-access-token', '--target-org', $Org, '--json') 120
  try { $tj = ConvertFrom-SfJson $t.Out; if ($tj.result -and $tj.result.accessToken) { $token = [string]$tj.result.accessToken } } catch {}
  if (-not $token -or $token -notmatch '!') {
    throw "Could not get an access token for $Org. Disconnect the org and connect it again, or update the Salesforce CLI (sf update)."
  }
  $s = @{ Token = $token; Url = ([string]$j.result.instanceUrl).TrimEnd('/'); Username = $j.result.username }
  $script:Sessions[$Org] = $s
  $s
}

# Calls the org's REST or SOAP API, refreshing the session once if it has expired.
function Invoke-OrgApi([string]$Org, [string]$Method, [string]$Path, [string]$Body, [string]$ContentType, [switch]$Soap) {
  $r = $null
  for ($i = 0; $i -lt 2; $i++) {
    $s = Get-OrgSession $Org -Refresh:($i -gt 0)
    if ($Soap) {
      $b = $Body.Replace('{{SESSION}}', [Security.SecurityElement]::Escape($s.Token))
      $h = @{ SOAPAction = '""' }
    } else {
      $b = $Body
      $h = @{ Authorization = "Bearer $($s.Token)" }
    }
    $r = Invoke-Http $Method ($s.Url + $Path) $h $b $ContentType
    if ($r.Status -eq 401 -or $r.Body -match 'INVALID_SESSION_ID') { continue }
    return $r
  }
  $r
}

# REST GET that returns parsed JSON, or throws Salesforce's own error message.
function Get-OrgJson([string]$Org, [string]$Path) {
  $r = Invoke-OrgApi $Org 'GET' $Path
  $j = $null
  try { $j = $r.Body | ConvertFrom-Json } catch {}
  if ($r.Status -ge 400 -or $null -eq $j) {
    $msg = $r.Body
    if ($j) { $msg = (@($j) | ForEach-Object { "$($_.errorCode): $($_.message)" }) -join '; ' }
    throw "Salesforce returned HTTP $($r.Status) for $Org. $msg"
  }
  $j
}

# ---------- input validation ----------

function Assert-Match($Value, [string]$Pattern, [string]$What) {
  $s = [string]$Value
  if ($s -notmatch $Pattern) { throw "Invalid $What" }
  $s
}
function Assert-Org($v) { Assert-Match $v '^[\w.@+\-]{1,150}$' 'org' }
function Assert-PkgName($v) { Assert-Match $v '^[\w\-]{1,80}$' 'package name' }
function Assert-JobId($v) { Assert-Match $v '^0Af[A-Za-z0-9]{12,15}$' 'deployment id' }
function Assert-Version($v) { Assert-Match $v '^\d{2,3}\.0$' 'API version' }

function Get-PackageZip([string]$Name) {
  $dir = Join-Path (Join-Path $PkgRoot $Name) 'retrieved'
  if (-not (Test-Path $dir)) { return $null }
  $zip = Get-ChildItem -Path $dir -Filter *.zip -Recurse | Select-Object -First 1
  if ($zip) { $zip.FullName } else { $null }
}

# Returns what to deploy for a package: its zip, or a fixed-up copy when it has a CustomSite whose site admin or
# guest record owner is a username that doesn't exist in the target (sandbox usernames differ per org). Those are
# mapped to the same user in the target where one exists, otherwise to the target's connected user.
function Get-DeploySource([string]$Name, [string]$Org) {
  $zip = Get-PackageZip $Name
  if (-not $zip) { return $null }
  $out = @{ Path = $zip; Fixes = @() }
  $dir = Join-Path (Join-Path $PkgRoot $Name) 'deploy'
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  $tmp = "$dir-tmp"
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $sites = @(Get-ChildItem -Path $tmp -Filter *.site -Recurse | Where-Object { $_.Directory.Name -eq 'sites' })
  $rx = '<(siteAdmin|siteGuestRecordDefaultOwner)>([^<]+)</\1>'
  $users = @($sites | ForEach-Object { [regex]::Matches([IO.File]::ReadAllText($_.FullName), $rx) | ForEach-Object { $_.Groups[2].Value } } | Sort-Object -Unique)
  if (-not $users.Count) { Remove-Item -Recurse -Force $tmp; return $out }

  $ver = '60.0'
  try { $m = [IO.File]::ReadAllText((Join-Path (Join-Path $PkgRoot $Name) 'meta.json')) | ConvertFrom-Json; if ($m.apiVersion) { $ver = $m.apiVersion } } catch {}
  $me = (Get-OrgSession $Org).Username
  $oq = [uri]::EscapeDataString('SELECT IsSandbox FROM Organization')
  $isSandbox = [bool]@((Get-OrgJson $Org "/services/data/v$ver/query?q=$oq").records)[0].IsSandbox
  $tgtSuffix = ''
  if ($isSandbox -and $me -match '\.([^.@]+)$') { $tgtSuffix = $Matches[1] }

  # The same person in the target, best first: the username itself, then with the target's sandbox suffix
  # (sandbox usernames are the production username + .<sandbox name>), or without a suffix in production.
  $cands = @{}
  foreach ($u in $users) {
    $base = $u
    if ($u -match '^(.+@.+\..+)\.[^.@]+$') { $base = $Matches[1] }
    $c = @($u)
    if ($tgtSuffix) { $c += @("$base.$tgtSuffix", "$u.$tgtSuffix") } else { $c += $base }
    $cands[$u] = @($c | Select-Object -Unique)
  }
  $all = @($cands.Values | ForEach-Object { $_ } | Sort-Object -Unique)
  $in = ($all | ForEach-Object { "'" + ($_ -replace "'", "\'") + "'" }) -join ','
  $q = [uri]::EscapeDataString("SELECT Username FROM User WHERE IsActive = true AND Username IN ($in)")
  $found = @((Get-OrgJson $Org "/services/data/v$ver/query?q=$q").records | ForEach-Object { $_.Username.ToLower() })
  $map = @{}
  foreach ($u in $users) {
    $hit = @($cands[$u] | Where-Object { $found -contains $_.ToLower() } | Select-Object -First 1)
    if (-not $hit.Count) { $map[$u] = @{ To = $me; Fallback = $true } }
    elseif ($hit[0] -ne $u) { $map[$u] = @{ To = $hit[0]; Fallback = $false } }
  }
  if (-not $map.Count) { Remove-Item -Recurse -Force $tmp; return $out }

  foreach ($f in $sites) {
    $text = [IO.File]::ReadAllText($f.FullName)
    $new = [regex]::Replace($text, $rx, {
      param($mt)
      $field = $mt.Groups[1].Value; $u = $mt.Groups[2].Value
      if (-not $map.ContainsKey($u)) { return $mt.Value }
      $to = $map[$u].To
      $out.Fixes += "CustomSite $($f.BaseName) ${field}: $u -> $to" + $(if ($map[$u].Fallback) { ' (no matching user in the target, so your connected user is used; change it in the site''s Administration > Preferences if needed)' } else { '' })
      "<$field>$to</$field>"
    })
    if ($new -ne $text) { [IO.File]::WriteAllText($f.FullName, $new, $Utf8) }
  }
  $pk = Get-ChildItem -Path $tmp -Filter package.xml -Recurse | Sort-Object { $_.FullName.Length } | Select-Object -First 1
  Move-Item $pk.DirectoryName $dir
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  $out.Path = $dir
  $out
}

function Assert-BackupId($v) { Assert-Match $v '^[\w\-]{1,160}$' 'backup id' }

# Builds the rollback folder from a backup: the target's previous versions, with package.xml limited to what existed,
# plus destructiveChangesPost.xml for components the deploy added. sf zips the folder itself when deploying it.
function New-RollbackDir([string]$BackupDir, [string]$PackageXml, [string]$DestructiveXml) {
  $rb = Join-Path $BackupDir 'rollback'
  $tmp = Join-Path $BackupDir 'rollback-tmp'
  foreach ($p in $rb, $tmp) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
  $src = Get-ChildItem -Path (Join-Path $BackupDir 'retrieved') -Filter *.zip -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($src) {
    Expand-Archive -Path $src.FullName -DestinationPath $tmp -Force
    $pk = Get-ChildItem -Path $tmp -Filter package.xml -Recurse | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if ($pk) { Move-Item $pk.DirectoryName $rb } else { Move-Item $tmp $rb }
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  } else {
    $null = New-Item -ItemType Directory -Force -Path $rb
  }
  [IO.File]::WriteAllText((Join-Path $rb 'package.xml'), $PackageXml, $Utf8)
  if ($DestructiveXml) { [IO.File]::WriteAllText((Join-Path $rb 'destructiveChangesPost.xml'), $DestructiveXml, $Utf8) }
  $rb
}

function Add-DeployLog([string]$Name, [string]$Line) {
  $f = Join-Path (Join-Path $PkgRoot $Name) 'deploys.jsonl'
  [IO.File]::AppendAllText($f, (($Line -replace "[\r\n]", ' ') + "`n"), $Utf8)
}

# ---------- responses ----------

function Send-Response($Ctx, [int]$Code, [string]$Type, [string]$Text) {
  $bytes = $Utf8.GetBytes($Text)
  $Ctx.Response.StatusCode = $Code
  $Ctx.Response.ContentType = "$Type; charset=utf-8"
  $Ctx.Response.Headers['Cache-Control'] = 'no-store'
  $Ctx.Response.ContentLength64 = $bytes.Length
  $Ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Ctx.Response.OutputStream.Close()
}
function Send-Json($Ctx, $Obj, [int]$Code = 200) {
  Send-Response $Ctx $Code 'application/json' (ConvertTo-Json -InputObject $Obj -Depth 8 -Compress)
}

# ---------- routes ----------

function Handle-Request($Ctx) {
  $req = $Ctx.Request
  $path = $req.Url.AbsolutePath
  $hostHeader = [string]$req.Headers['Host']
  if ($hostHeader -ne "localhost:$Port" -and $hostHeader -ne "127.0.0.1:$Port") {
    Send-Response $Ctx 403 'text/plain' 'Forbidden'; return
  }
  if ($path -eq '/' -or $path -eq '/index.html') {
    $html = [IO.File]::ReadAllText((Join-Path $Root 'index.html'), $Utf8).Replace('{{TOKEN}}', $Token)
    Send-Response $Ctx 200 'text/html' $html; return
  }
  if (-not $path.StartsWith('/api/')) { Send-Response $Ctx 404 'text/plain' 'Not found'; return }
  if ($req.Headers['X-Token'] -ne $Token) { Send-Json $Ctx @{ error = 'Forbidden' } 403; return }

  $b = $null
  if ($req.HasEntityBody) {
    $sr = New-Object IO.StreamReader($req.InputStream, $Utf8)
    $text = $sr.ReadToEnd(); $sr.Close()
    if ($text) { $b = $text | ConvertFrom-Json }
  }

  switch ($path) {
    '/api/health' {
      # 'stale' tells the page that server.ps1 changed after this server started, so it needs a restart.
      $stale = (Get-Item (Join-Path $Root 'server.ps1')).LastWriteTime -gt $script:StartedAt
      Send-Json $Ctx @{ sf = [bool]$SfPath; sfPath = $SfPath; sfVersion = $script:SfVersion; packagesDir = $PkgRoot; stale = $stale }
      return
    }
    '/api/orgs' {
      $r = Invoke-Sf @('org', 'list', '--json') 120
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/login' {
      $alias = Assert-Match $b.alias '^[\w.\-]{1,60}$' 'alias'
      $url = Assert-Match $b.instanceUrl '^https://[\w.\-]+(:\d+)?/?$' 'login URL'
      $r = Invoke-Sf @('org', 'login', 'web', '--alias', $alias, '--instance-url', $url, '--json') 600
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/alias' {
      # Renames a connected org's alias in the Salesforce CLI (an empty alias just removes the old one).
      $org = Assert-Org $b.org
      $alias = [string]$b.alias
      if ($alias) { $alias = Assert-Match $alias '^[\w.\-]{1,60}$' 'alias' }
      $old = [string]$b.old
      if ($old) { $old = Assert-Match $old '^[\w.\-]{1,60}$' 'alias' }
      $r = $null
      if ($alias) { $r = Invoke-Sf @('alias', 'set', "$alias=$org", '--json') 120 }
      if ($old -and $old -ne $alias) { $u = Invoke-Sf @('alias', 'unset', $old, '--json') 120; if (-not $r) { $r = $u } }
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/logout' {
      $org = Assert-Org $b.org
      $r = Invoke-Sf @('org', 'logout', '--target-org', $org, '--no-prompt', '--json') 120
      $script:Sessions.Remove($org)
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/orginfo' {
      $org = Assert-Org $b.org
      $s = Get-OrgSession $org -Refresh
      $versions = Get-OrgJson $org '/services/data/'
      $max = ($versions | ForEach-Object { [double]::Parse($_.version, [Globalization.CultureInfo]::InvariantCulture) } | Measure-Object -Maximum).Maximum
      $ver = $max.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
      $q = [uri]::EscapeDataString('SELECT Name, IsSandbox, OrganizationType FROM Organization')
      $o = @((Get-OrgJson $org "/services/data/v$ver/query?q=$q").records)[0]
      $uq = [uri]::EscapeDataString("SELECT Name FROM User WHERE Username = '" + ($s.Username -replace "'", "\'") + "'")
      $u = @((Get-OrgJson $org "/services/data/v$ver/query?q=$uq").records)
      Send-Json $Ctx @{
        org = $org; apiVersion = $ver; instanceUrl = $s.Url; username = $s.Username
        name = $o.Name; isSandbox = [bool]$o.IsSandbox; orgType = $o.OrganizationType
        userFullName = $(if ($u) { $u[0].Name } else { '' })
      }
      return
    }
    '/api/listmetadata' {
      $org = Assert-Org $b.org
      $ver = Assert-Version $b.apiVersion
      $qs = foreach ($q in $b.queries) {
        $t = Assert-Match $q.type '^[A-Za-z]{2,80}$' 'metadata type'
        $folder = ''
        if ($q.folder) { $folder = '<met:folder>' + [Security.SecurityElement]::Escape([string]$q.folder) + '</met:folder>' }
        "<met:queries>$folder<met:type>$t</met:type></met:queries>"
      }
      $envelope = '<?xml version="1.0" encoding="UTF-8"?>' +
        '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
        '<soapenv:Header><met:SessionHeader><met:sessionId>{{SESSION}}</met:sessionId></met:SessionHeader></soapenv:Header>' +
        '<soapenv:Body><met:listMetadata>' + ($qs -join '') + "<met:asOfVersion>$ver</met:asOfVersion></met:listMetadata></soapenv:Body></soapenv:Envelope>"
      $r = Invoke-OrgApi $org 'POST' "/services/Soap/m/$ver" $envelope 'text/xml; charset=utf-8' -Soap
      Send-Response $Ctx 200 'text/xml' $r.Body
      return
    }
    '/api/retrieve' {
      $org = Assert-Org $b.org
      $name = Assert-PkgName $b.name
      $dir = Join-Path $PkgRoot $name
      foreach ($sub in 'retrieved', 'contents') {
        $p = Join-Path $dir $sub
        if (Test-Path $p) { Remove-Item -Recurse -Force $p }
      }
      $null = New-Item -ItemType Directory -Force -Path $dir
      $manifest = Join-Path $dir 'package.xml'
      [IO.File]::WriteAllText($manifest, [string]$b.packageXml, $Utf8)
      $meta = @{
        name = $name; sourceOrg = $org; sourceLabel = [string]$b.sourceLabel; apiVersion = [string]$b.apiVersion
        components = [int]$b.count; note = [string]$b.note; created = (Get-Date).ToString('o')
      }
      [IO.File]::WriteAllText((Join-Path $dir 'meta.json'), (ConvertTo-Json -InputObject $meta -Compress), $Utf8)
      $r = Invoke-Sf @('project', 'retrieve', 'start', '--manifest', $manifest, '--target-metadata-dir', (Join-Path $dir 'retrieved'),
        '--zip-file-name', 'unpackaged.zip', '--target-org', $org, '--wait', '60', '--json') 3900
      $zip = Get-PackageZip $name
      if ($zip) {
        try { Expand-Archive -Path $zip -DestinationPath (Join-Path $dir 'contents') -Force } catch { Write-Log "Could not unzip for browsing: $($_.Exception.Message)" 'Yellow' }
      }
      Send-Json $Ctx @{ ok = [bool]$zip; zip = $zip; dir = $dir; raw = $r.Out; err = $r.Err }
      return
    }
    '/api/deploy' {
      $org = Assert-Org $b.target
      $name = Assert-PkgName $b.pkg
      $mode = Assert-Match $b.mode '^(validate|deploy|quick|rollback)$' 'mode'
      $level = Assert-Match $b.testLevel '^(NoTestRun|RunSpecifiedTests|RunLocalTests|RunAllTestsInOrg)$' 'test level'
      $testArgs = @('--test-level', $level)
      if ($level -eq 'RunSpecifiedTests') {
        $tests = @($b.tests | Where-Object { $_ })
        if (-not $tests.Count) { throw 'List at least one test class for RunSpecifiedTests.' }
        foreach ($t in $tests) { $testArgs += @('--tests', (Assert-Match $t '^[\w.]{1,255}$' 'test name')) }
      }
      $backupId = ''
      if ($b.backupId) { $backupId = Assert-BackupId $b.backupId }
      $fixes = @()
      if ($mode -eq 'quick') {
        $a = @('project', 'deploy', 'quick', '--job-id', (Assert-JobId $b.jobId))
      } elseif ($mode -eq 'rollback') {
        $rb = Join-Path $PkgRoot "$name\backups\$backupId\rollback"
        if (-not $backupId -or -not (Test-Path (Join-Path $rb 'package.xml'))) { throw 'That rollback point has no rollback package.' }
        $a = @('project', 'deploy', 'start', '--metadata-dir', $rb) + $testArgs
      } else {
        $src = Get-DeploySource $name $org
        if (-not $src) { throw "Package '$name' has no retrieved zip. Build it first." }
        $zip = $src.Path
        $fixes = @($src.Fixes)
        foreach ($f in $fixes) { Write-Log $f 'Yellow' }
        if ($mode -eq 'deploy') { $a = @('project', 'deploy', 'start', '--metadata-dir', $zip) + $testArgs }
        elseif ($level -eq 'NoTestRun') { $a = @('project', 'deploy', 'start', '--dry-run', '--metadata-dir', $zip) + $testArgs }
        else { $a = @('project', 'deploy', 'validate', '--metadata-dir', $zip) + $testArgs }
      }
      $r = Invoke-Sf ($a + @('--target-org', $org, '--async', '--json')) 600
      $id = ''
      try { $id = (ConvertFrom-SfJson $r.Out).result.id } catch {}
      Add-DeployLog $name (ConvertTo-Json -Compress -InputObject @{ time = (Get-Date).ToString('o'); event = 'start'; mode = $mode; target = $org; testLevel = $level; jobId = $id; backupId = $backupId })
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err; fixes = $fixes }
      return
    }
    '/api/backup' {
      # Retrieves the package's components from the target as they are now, before a deploy changes them.
      $org = Assert-Org $b.target
      $name = Assert-PkgName $b.pkg
      $manifest = Join-Path (Join-Path $PkgRoot $name) 'package.xml'
      if (-not (Test-Path $manifest)) { throw "Package '$name' has no package.xml." }
      $id = ($org -replace '[^\w\-]', '_') + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
      $bdir = Join-Path $PkgRoot "$name\backups\$id"
      $null = New-Item -ItemType Directory -Force -Path $bdir
      $r = Invoke-Sf @('project', 'retrieve', 'start', '--manifest', $manifest, '--target-metadata-dir', (Join-Path $bdir 'retrieved'),
        '--zip-file-name', 'backup.zip', '--target-org', $org, '--wait', '60', '--json') 3900
      Send-Json $Ctx @{ id = $id; raw = $r.Out; err = $r.Err }
      return
    }
    '/api/rollback/prepare' {
      $name = Assert-PkgName $b.pkg
      $id = Assert-BackupId $b.id
      $bdir = Join-Path $PkgRoot "$name\backups\$id"
      if (-not (Test-Path $bdir)) { throw "Backup $id not found." }
      $null = ([string]$b.meta) | ConvertFrom-Json
      $rb = New-RollbackDir $bdir ([string]$b.packageXml) ([string]$b.destructiveXml)
      [IO.File]::WriteAllText((Join-Path $bdir 'backup.json'), [string]$b.meta, $Utf8)
      Send-Json $Ctx @{ ok = $true; dir = $rb }
      return
    }
    '/api/report' {
      $org = Assert-Org $b.target
      $id = Assert-JobId $b.jobId
      $r = Invoke-Sf @('project', 'deploy', 'report', '--job-id', $id, '--target-org', $org, '--json') 300
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/cancel' {
      $org = Assert-Org $b.target
      $id = Assert-JobId $b.jobId
      $r = Invoke-Sf @('project', 'deploy', 'cancel', '--job-id', $id, '--target-org', $org, '--async', '--json') 300
      Send-Json $Ctx @{ raw = $r.Out; err = $r.Err }
      return
    }
    '/api/logdeploy' {
      $name = Assert-PkgName $b.pkg
      if (Test-Path (Join-Path $PkgRoot $name)) { Add-DeployLog $name ([string]$b.line) }
      Send-Json $Ctx @{ ok = $true }
      return
    }
    '/api/packages' {
      $list = @(Get-ChildItem -Path $PkgRoot -Directory | Sort-Object CreationTime -Descending | ForEach-Object {
        $d = $_.FullName
        $read = { param($f) $p = Join-Path $d $f; if (Test-Path $p) { [IO.File]::ReadAllText($p, $Utf8) } else { '' } }
        $backups = @(Get-ChildItem -Path (Join-Path $d 'backups') -Directory -ErrorAction SilentlyContinue |
          Where-Object { (Test-Path (Join-Path $_.FullName 'backup.json')) -and (Test-Path (Join-Path $_.FullName 'rollback\package.xml')) } |
          ForEach-Object { [IO.File]::ReadAllText((Join-Path $_.FullName 'backup.json'), $Utf8) })
        @{ name = $_.Name; meta = (& $read 'meta.json'); packageXml = (& $read 'package.xml'); deploys = (& $read 'deploys.jsonl'); hasZip = [bool](Get-PackageZip $_.Name); backups = $backups; archived = (Test-Path (Join-Path $d 'archived.flag')) }
      })
      Send-Json $Ctx @{ packages = $list }
      return
    }
    '/api/templates' {
      $f = Join-Path $Root 'templates.json'
      if ($b -and $null -ne $b.json) {
        $text = [string]$b.json
        $null = $text | ConvertFrom-Json  # refuse to save anything that isn't valid JSON
        if (Test-Path $f) { Copy-Item $f "$f.bak" -Force }
        [IO.File]::WriteAllText($f, $text, $Utf8)
      }
      $raw = '[]'
      if (Test-Path $f) { $raw = [IO.File]::ReadAllText($f, $Utf8) }
      Send-Json $Ctx @{ raw = $raw }
      return
    }
    '/api/package/archive' {
      $name = Assert-PkgName $b.pkg
      $dir = Join-Path $PkgRoot $name
      if (-not (Test-Path $dir)) { throw "Package '$name' not found." }
      $flag = Join-Path $dir 'archived.flag'
      if ($b.archived) { [IO.File]::WriteAllText($flag, (Get-Date).ToString('o'), $Utf8) }
      elseif (Test-Path $flag) { Remove-Item $flag -Force }
      Send-Json $Ctx @{ ok = $true }
      return
    }
    '/api/package/delete' {
      $name = Assert-PkgName $b.pkg
      $dir = Join-Path $PkgRoot $name
      if (-not (Test-Path $dir)) { throw "Package '$name' not found." }
      Remove-Item -Recurse -Force $dir
      Write-Log "Deleted package $name"
      Send-Json $Ctx @{ ok = $true }
      return
    }
    '/api/open' {
      $name = Assert-PkgName $b.pkg
      $dir = Join-Path $PkgRoot $name
      if (-not (Test-Path $dir)) { $dir = $PkgRoot }
      Start-Process explorer.exe $dir
      Send-Json $Ctx @{ ok = $true }
      return
    }
    '/api/shutdown' {
      Send-Json $Ctx @{ ok = $true }
      $script:Running = $false
      return
    }
    default { Send-Json $Ctx @{ error = "Unknown endpoint $path" } 404 }
  }
}

# ---------- start ----------

$script:SfVersion = ''
if ($SfPath) {
  try { $script:SfVersion = ((Invoke-Sf @('--version') 120).Out).Trim() } catch {}
  Write-Log "Salesforce CLI: $($script:SfVersion)" 'Green'
} else {
  Write-Log 'Salesforce CLI (sf) not found. Install it from https://developer.salesforce.com/tools/salesforcecli' 'Yellow'
}

$listener = $null
for ($p = $Port; $p -lt $Port + 10; $p++) {
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://localhost:$p/")
  try { $l.Start(); $listener = $l; $Port = $p; break } catch { $l.Close() }
}
if (-not $listener) { throw "Could not open a local port between $Port and $($Port + 9)." }

$url = "http://localhost:$Port/"
Write-Log "Metadata Mover is running at $url  (Ctrl+C or the Stop button to quit)" 'Green'
Write-Log "Packages are saved in $PkgRoot"
if (-not $NoBrowser) { Start-Process $url }

try {
  while ($script:Running) {
    $task = $listener.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(250)) { }
    $ctx = $task.Result
    try { Handle-Request $ctx }
    catch {
      Write-Log "Error: $($_.Exception.Message)" 'Red'
      try { Send-Json $ctx @{ error = $_.Exception.Message } 500 } catch {}
    }
  }
} finally {
  $listener.Stop(); $listener.Close()
  Write-Log 'Stopped.'
}
