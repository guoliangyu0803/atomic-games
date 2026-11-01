param(
    [int]$Port = 8000,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }

Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║      原子物理闯关 · 公网隧道（学生任意网络可访问） ║" -ForegroundColor Cyan
Write-Host "  ╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  正在启动本地服务器..." -ForegroundColor DarkGray

$srvArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'server.ps1'), '-NoBrowser', '-Port', "$Port")
$server = Start-Process -FilePath 'powershell' -ArgumentList $srvArgs -PassThru -WindowStyle Minimized
Start-Sleep -Milliseconds 2000

if ($server.HasExited) {
    Write-Host "  × 本地服务器启动失败，端口 $Port 可能被占用。" -ForegroundColor Red
    Write-Host "    换端口重试：  powershell -ExecutionPolicy Bypass -File tunnel.ps1 -Port 9000" -ForegroundColor Yellow
    exit 1
}

Write-Host "  本地服务器就绪： http://127.0.0.1:$Port/" -ForegroundColor DarkGreen
Write-Host "  正在连接公网隧道（约 5 秒）..." -ForegroundColor DarkGray

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.Arguments = '-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="' +
                 (Join-Path $env:TEMP 'known_hosts_lhr') +
                 '" -o ServerAliveInterval=30 -T -R 80:127.0.0.1:' + $Port + ' nokey@localhost.run'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.CreateNoWindow = $true

$tunnel = $null
$url = $null
try {
    $tunnel = [System.Diagnostics.Process]::Start($psi)

    for ($i = 0; $i -lt 20; $i++) {
        $task = $tunnel.StandardOutput.ReadLineAsync()
        if (-not $task.Wait(3000)) { break }
        $line = $task.Result
        if ($null -eq $line) { break }
        if ($line -match '(https://[a-z0-9]+\.lhr\.life)') {
            $url = $Matches[1]
            break
        }
    }

    if (-not $url) {
        Write-Host ""
        Write-Host "  × 没能拿到公网地址。可能原因：" -ForegroundColor Red
        Write-Host "    · 这台电脑没有联网，或 22 端口被网络环境限制" -ForegroundColor DarkGray
        Write-Host "    · localhost.run 暂时不可用，稍后重试即可" -ForegroundColor DarkGray
        Write-Host "    · 也可以用手机热点给电脑联网后重试" -ForegroundColor DarkGray
        exit 1
    }

    # 继续读走剩余输出，避免 ssh 因缓冲区满而卡住
    $null = $tunnel.StandardOutput.ReadToEndAsync()

    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "   公网地址（发给学生 / 生成二维码）：" -ForegroundColor Green
    Write-Host "   $url" -ForegroundColor Yellow
    Write-Host "  ═══════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  · 学生用手机流量也能打开，不需要和你同一个 WiFi" -ForegroundColor DarkGray
    Write-Host "  · 这个地址是临时的：关掉本窗口就失效，下次启动会变" -ForegroundColor DarkGray
    Write-Host "  · 电脑需要保持开机、不休眠" -ForegroundColor DarkGray
    Write-Host ""

    if (-not $NoBrowser) {
        try {
            $qrUri = ([System.Uri](Join-Path $root 'qr.html')).AbsoluteUri +
                     '?u=' + [System.Uri]::EscapeDataString($url + '/')
            Start-Process $qrUri
        } catch { }
    }

    Write-Host "  隧道运行中……按 Ctrl+C 或关窗口结束。" -ForegroundColor DarkGray
    $tunnel.WaitForExit()
}
finally {
    if ($tunnel -and -not $tunnel.HasExited) { try { $tunnel.Kill() } catch { } }
    if ($server -and -not $server.HasExited) { try { $server.Kill() } catch { } }
    Write-Host ""
    Write-Host "  隧道和本地服务器都已停止。" -ForegroundColor DarkGray
}
