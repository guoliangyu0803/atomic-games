param(
    [int]$Port = 8000,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$rootFull = [System.IO.Path]::GetFullPath($root)

# ---------------- 找一个局域网 IP ----------------
function Get-LanAddresses {
    $list = @()
    try {
        $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
        foreach ($nic in $nics) {
            if ($nic.OperationalStatus -ne 'Up') { continue }
            if ($nic.NetworkInterfaceType -eq 'Loopback') { continue }
            $props = $nic.GetIPProperties()
            foreach ($ua in $props.UnicastAddresses) {
                $ip = $ua.Address
                if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                $s = $ip.ToString()
                if ($s -like '127.*' -or $s -like '169.254.*') { continue }
                $list += $s
            }
        }
    } catch { }
    return $list
}

$lanIps = @(Get-LanAddresses)
# 优先 192.168.x / 10.x / 172.16-31.x
$preferred = @()
foreach ($ip in $lanIps) {
    if ($ip -like '192.168.*' -or $ip -like '10.*' -or $ip -match '^172\.(1[6-9]|2[0-9]|3[01])\.') {
        $preferred += $ip
    }
}
$showIps = if ($preferred.Count -gt 0) { $preferred } else { $lanIps }

# ---------------- 端口 ----------------
$listener = $null
$usedPort = $Port
for ($tryPort = $Port; $tryPort -lt ($Port + 12); $tryPort++) {
    try {
        $candidate = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $tryPort)
        $candidate.Start()
        $listener = $candidate
        $usedPort = $tryPort
        break
    } catch {
        continue
    }
}
if ($null -eq $listener) {
    Write-Host ""
    Write-Host "  × 从 $Port 开始连续 12 个端口都被占用，启动失败。" -ForegroundColor Red
    Write-Host "    可以换一个端口重试：  .\server.ps1 -Port 9000" -ForegroundColor Yellow
    exit 1
}

# ---------------- 响应工具 ----------------
$mimeMap = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.mp3'  = 'audio/mpeg'
    '.woff2' = 'font/woff2'
    '.txt'  = 'text/plain; charset=utf-8'
}

function Send-Response {
    param($Stream, [int]$Code, [string]$Reason, [string]$Mime, [byte[]]$Body)
    $head = "HTTP/1.1 $Code $Reason`r`n" +
            "Content-Type: $Mime`r`n" +
            "Content-Length: $($Body.Length)`r`n" +
            "Cache-Control: no-store`r`n" +
            "Connection: close`r`n" +
            "`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Send-Text {
    param($Stream, [int]$Code, [string]$Reason, [string]$Text)
    $body = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-Response -Stream $Stream -Code $Code -Reason $Reason -Mime 'text/plain; charset=utf-8' -Body $body
}

# ---------------- 启动信息 ----------------
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║        原子物理闯关 · 课堂局域网服务器           ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  本机打开：  http://127.0.0.1:$usedPort/" -ForegroundColor Green
if ($showIps.Count -gt 0) {
    foreach ($ip in $showIps) {
        Write-Host "  学生扫码：  http://${ip}:$usedPort/" -ForegroundColor Yellow
    }
} else {
    Write-Host "  × 没找到局域网 IP：请确认电脑已连接 WiFi 或网线。" -ForegroundColor Red
}
Write-Host ""
Write-Host "  · 学生手机必须连【同一个 WiFi】" -ForegroundColor DarkGray
Write-Host "  · 若打不开，多半是 Windows 防火墙拦了：弹窗时选“允许访问”" -ForegroundColor DarkGray
Write-Host "  · 关掉这个窗口就停止服务" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoBrowser) {
    try { Start-Process ("http://127.0.0.1:$usedPort/qr.html") } catch { }
}

# ---------------- 主循环 ----------------
$count = 0
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $null
        try {
            $client.ReceiveTimeout = 5000
            $stream = $client.GetStream()

            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }

            # 吃掉请求头
            $guard = 0
            while ($guard -lt 100) {
                $guard++
                $line = $reader.ReadLine()
                if ($null -eq $line -or $line -eq '') { break }
            }

            $parts = $requestLine -split ' '
            $method = $parts[0]
            $rawPath = if ($parts.Count -ge 2) { $parts[1] } else { '/' }

            if ($method -ne 'GET' -and $method -ne 'HEAD') {
                Send-Text -Stream $stream -Code 405 -Reason 'Method Not Allowed' -Text 'Only GET is supported.'
                $client.Close(); continue
            }

            $pathOnly = ($rawPath -split '\?')[0]
            try { $pathOnly = [System.Uri]::UnescapeDataString($pathOnly) } catch { }
            if ([string]::IsNullOrEmpty($pathOnly)) { $pathOnly = '/' }

            if ($pathOnly -eq '/') { $pathOnly = '/index.html' }
            $rel = $pathOnly.TrimStart('/')
            $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))

            # 目录穿越防护：比较时带上目录分隔符，
            # 否则 atomic-games-evil 这类同前缀目录会被误判为在根目录内
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $rootPrefix = $rootFull.TrimEnd($sep) + $sep
            if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Send-Text -Stream $stream -Code 403 -Reason 'Forbidden' -Text 'Forbidden.'
                $client.Close(); continue
            }

            if (Test-Path -LiteralPath $full -PathType Container) {
                $full = Join-Path $full 'index.html'
            }

            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                Send-Text -Stream $stream -Code 404 -Reason 'Not Found' -Text "404 - 找不到 $pathOnly"
                Write-Host ("  {0,-8} {1}" -f '404', $pathOnly) -ForegroundColor DarkYellow
                $client.Close(); continue
            }

            # 只对外提供页面资源：避免学生直接下载 server.ps1 / 启动脚本 / README
            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            $allowedExt = @('.html', '.htm', '.css', '.js', '.json', '.png', '.jpg', '.jpeg',
                            '.gif', '.svg', '.ico', '.woff2', '.mp3', '.txt')
            if ($allowedExt -notcontains $ext) {
                Send-Text -Stream $stream -Code 403 -Reason 'Forbidden' -Text 'Forbidden.'
                $client.Close(); continue
            }

            $mime = if ($mimeMap.ContainsKey($ext)) { $mimeMap[$ext] } else { 'application/octet-stream' }
            $bytes = [System.IO.File]::ReadAllBytes($full)

            if ($method -eq 'HEAD') {
                Send-Response -Stream $stream -Code 200 -Reason 'OK' -Mime $mime -Body ([byte[]]@())
            } else {
                Send-Response -Stream $stream -Code 200 -Reason 'OK' -Mime $mime -Body $bytes
            }

            $count++
            if ($pathOnly -match '\.html$' -and $pathOnly -notmatch '/qr\.html') {
                Write-Host ("  {0,-8} {1}" -f '200', $pathOnly) -ForegroundColor DarkGreen
            }
        } catch {
            # 单个连接出错不影响整体服务
        } finally {
            try { if ($stream) { $stream.Close() } } catch { }
            try { $client.Close() } catch { }
        }
    }
}
finally {
    try { $listener.Stop() } catch { }
    Write-Host ""
    Write-Host "  服务已停止。" -ForegroundColor DarkGray
}
