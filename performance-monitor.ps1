# performance-monitor.ps1
Clear-Host
Write-Host "================================" -ForegroundColor Cyan
Write-Host "    📊 PERFORMANCE MONITOR" -ForegroundColor White
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

while ($true) {
    Clear-Host
    Write-Host "📊 Performance Monitor - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ""
    
    # Check Node processes
    $node = Get-Process -Name node -ErrorAction SilentlyContinue
    if ($node) {
        Write-Host "🟢 Node.js Processes:" -ForegroundColor Green
        $node | ForEach-Object {
            $memMB = [math]::Round($_.WorkingSet / 1MB, 2)
            $cpu = [math]::Round($_.CPU, 1)
            $color = if ($memMB -gt 800) { "Red" } elseif ($memMB -gt 500) { "Yellow" } else { "Green" }
            Write-Host "   PID $($_.Id): $memMB MB | CPU: $cpu s | Threads: $($_.Threads.Count)" -ForegroundColor $color
        }
    } else {
        Write-Host "🔴 Node.js not running" -ForegroundColor Red
    }
    Write-Host ""
    
    # System memory
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $free = [math]::Round($os.FreePhysicalMemory/1MB, 2)
    $total = [math]::Round($os.TotalVisibleMemorySize/1MB, 2)
    $used = $total - $free
    $percent = [math]::Round(($used/$total)*100, 1)
    Write-Host "💾 System Memory:" -ForegroundColor Yellow
    Write-Host "   Free: $free MB" -ForegroundColor $(if ($free -gt 2000) {"Green"} else {"Red"})
    Write-Host "   Used: $used MB ($percent%)" -ForegroundColor $(if ($percent -lt 70) {"Green"} else {"Red"})
    Write-Host ""
    
    # Page load time
    Write-Host "🌐 Application Status:" -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 2
        Write-Host "   ✅ Application running (Status: $($response.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Application not accessible" -ForegroundColor Red
    }
    Write-Host ""
    
    Write-Host "Press Ctrl+C to exit" -ForegroundColor Gray
    Start-Sleep -Seconds 3
}
