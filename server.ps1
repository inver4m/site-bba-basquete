# =====================================================================
# BBA LEAGUE - SERVIDOR WEB LOCAL & API REST
# =====================================================================
param(
    [int]$Port = 8080
)

$RootDir = "c:\Users\Buda\Documents\BBA1"

$mimeMap = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.txt'  = 'text/plain; charset=utf-8'
}

$feedbackFile = Join-Path $RootDir "feedbacks.json"
if (-not (Test-Path $feedbackFile)) {
    "[]" | Out-File -FilePath $feedbackFile -Encoding UTF8
}

$matchesFile = Join-Path $RootDir "matches.json"
if (-not (Test-Path $matchesFile)) {
    "[]" | Out-File -FilePath $matchesFile -Encoding UTF8
}

$awardsFile = Join-Path $RootDir "awards.json"
if (-not (Test-Path $awardsFile)) {
    "{}" | Out-File -FilePath $awardsFile -Encoding UTF8
}

$endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)
$listener = New-Object System.Net.Sockets.TcpListener($endpoint)
$listener.Start()

# Detect active IP addresses
$lanIP = "localhost"
$radminIP = ""
try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' }
    foreach ($ip in $ips) {
        if ($ip.InterfaceAlias -match "Radmin") {
            $radminIP = $ip.IPAddress
        } elseif (-not $lanIP -or $lanIP -eq "localhost") {
            $lanIP = $ip.IPAddress
        }
    }
} catch {}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   BBA LEAGUE - SERVIDOR LOCAL & API OFICIAL              " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " [1] Seu Computador (Local):   http://localhost:$Port" -ForegroundColor Cyan
if ($lanIP -and $lanIP -ne "localhost") {
    Write-Host " [2] Rede Local (Mesmo Wi-Fi): http://${lanIP}:$Port" -ForegroundColor Cyan
}
if ($radminIP) {
    Write-Host " [3] Radmin VPN (Sua Equipe):  http://${radminIP}:$Port" -ForegroundColor Magenta
}
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Servidor rodando... Pressione Ctrl + C para encerrar.`n" -ForegroundColor Gray

while ($listener.Server.IsBound) {
    try {
        $client = $listener.AcceptTcpClient()
    } catch {
        break
    }
    
    try {
        $stream = $client.GetStream()
        $buffer = New-Object byte[] 65536
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -le 0) { $client.Close(); continue }
        
        $rawRequest = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
        $firstLine = ($rawRequest -split "`r?`n")[0]
        $reqParts = $firstLine -split " "
        if ($reqParts.Length -lt 2) { $client.Close(); continue }
        
        $method = $reqParts[0].ToUpper()
        $urlWithQuery = $reqParts[1]
        $pathOnly = ($urlWithQuery -split '\?')[0]
        if ($pathOnly -eq "/" -or $pathOnly -eq "") { $pathOnly = "/index.html" }
        $cleanPath = [System.Uri]::UnescapeDataString($pathOnly).TrimStart('/')
        
        # -----------------------------------------------------------------
        # API: POST /api/feedback
        # -----------------------------------------------------------------
        if ($method -eq "POST" -and $pathOnly -eq "/api/feedback") {
            $bodyIndex = $rawRequest.IndexOf("`r`n`r`n")
            if ($bodyIndex -lt 0) { $bodyIndex = $rawRequest.IndexOf("`n`n") }
            $body = ""
            if ($bodyIndex -ge 0) {
                $body = $rawRequest.Substring($bodyIndex).Trim()
            }
            
            $entry = @{
                id        = (Get-Date -Format "yyyyMMdd-HHmmss")
                timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                author    = "Membro da Equipe"
                role      = "Equipe"
                message   = ""
            }
            
            try {
                $parsed = $body | ConvertFrom-Json
                if ($parsed.author) { $entry.author = [string]$parsed.author }
                if ($parsed.role)   { $entry.role   = [string]$parsed.role }
                if ($parsed.message){ $entry.message= [string]$parsed.message }
            } catch {}
            
            try {
                $existing = @()
                if (Test-Path $feedbackFile) {
                    try { $existing = (Get-Content $feedbackFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
                }
                if (-not ($existing -is [System.Collections.IList])) {
                    $existing = @($existing)
                }
                $list = New-Object System.Collections.ArrayList
                foreach ($item in $existing) { if ($item) { [void]$list.Add($item) } }
                [void]$list.Add($entry)
                ($list | ConvertTo-Json -Depth 5) | Out-File -FilePath $feedbackFile -Encoding UTF8
                
                Write-Host "[FEEDBACK $(Get-Date -Format 'HH:mm:ss')] De: $($entry.author) | Mensagem: $($entry.message)" -ForegroundColor Green
            } catch {
                Write-Host "Erro ao salvar feedback: $_" -ForegroundColor Red
            }
            
            $respText = '{"success":true,"message":"Feedback enviado com sucesso!"}'
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respText)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }
        
        # -----------------------------------------------------------------
        # API: GET /api/feedbacks
        # -----------------------------------------------------------------
        if ($method -eq "GET" -and $pathOnly -eq "/api/feedbacks") {
            $respData = "[]"
            if (Test-Path $feedbackFile) {
                $respData = Get-Content $feedbackFile -Raw -Encoding UTF8
            }
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respData)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }
        
        # -----------------------------------------------------------------
        # API: GET /api/matches
        # -----------------------------------------------------------------
        if ($method -eq "GET" -and $pathOnly -eq "/api/matches") {
            $respData = "[]"
            if (Test-Path $matchesFile) {
                $respData = Get-Content $matchesFile -Raw -Encoding UTF8
            }
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respData)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }
        
        # -----------------------------------------------------------------
        # API: POST /api/matches
        # -----------------------------------------------------------------
        if ($method -eq "POST" -and $pathOnly -eq "/api/matches") {
            $bodyIndex = $rawRequest.IndexOf("`r`n`r`n")
            if ($bodyIndex -lt 0) { $bodyIndex = $rawRequest.IndexOf("`n`n") }
            $body = ""
            if ($bodyIndex -ge 0) {
                $body = $rawRequest.Substring($bodyIndex).Trim()
            }
            
            try {
                if ($body) {
                    [System.IO.File]::WriteAllText($matchesFile, $body, [System.Text.Encoding]::UTF8)
                    Write-Host "[MATCHES ATUALIZADOS $(Get-Date -Format 'HH:mm:ss')] O Criador atualizou as partidas!" -ForegroundColor Green
                }
            } catch {
                Write-Host "Erro ao salvar partidas: $_" -ForegroundColor Red
            }
            
            $respText = '{"success":true,"message":"Partidas salvas com sucesso!"}'
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respText)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }

        # -----------------------------------------------------------------
        # API: GET /api/awards
        # -----------------------------------------------------------------
        if ($method -eq "GET" -and $pathOnly -eq "/api/awards") {
            $respData = "{}"
            if (Test-Path $awardsFile) {
                $respData = Get-Content $awardsFile -Raw -Encoding UTF8
            }
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respData)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }

        # -----------------------------------------------------------------
        # API: POST /api/awards
        # -----------------------------------------------------------------
        if ($method -eq "POST" -and $pathOnly -eq "/api/awards") {
            $bodyIndex = $rawRequest.IndexOf("`r`n`r`n")
            if ($bodyIndex -lt 0) { $bodyIndex = $rawRequest.IndexOf("`n`n") }
            $body = ""
            if ($bodyIndex -ge 0) {
                $body = $rawRequest.Substring($bodyIndex).Trim()
            }
            
            try {
                if ($body) {
                    [System.IO.File]::WriteAllText($awardsFile, $body, [System.Text.Encoding]::UTF8)
                    Write-Host "[AWARDS ATUALIZADOS $(Get-Date -Format 'HH:mm:ss')] O Criador atualizou os premios!" -ForegroundColor Green
                }
            } catch {
                Write-Host "Erro ao salvar premios: $_" -ForegroundColor Red
            }
            
            $respText = '{"success":true,"message":"Premios salvos com sucesso!"}'
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respText)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Length: $($respBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($respBytes, 0, $respBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }
        
        # -----------------------------------------------------------------
        # OPTIONS (CORS PREFLIGHT)
        # -----------------------------------------------------------------
        if ($method -eq "OPTIONS") {
            $headers = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Flush()
            $client.Close()
            continue
        }
        
        # -----------------------------------------------------------------
        # STATIC FILE SERVING
        # -----------------------------------------------------------------
        $targetFile = Join-Path $RootDir $cleanPath
        
        if (Test-Path $targetFile -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($targetFile).ToLower()
            $contentType = "application/octet-stream"
            if ($mimeMap.ContainsKey($ext)) {
                $contentType = $mimeMap[$ext]
            }
            
            $fileBytes = [System.IO.File]::ReadAllBytes($targetFile)
            $headers = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($fileBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($fileBytes, 0, $fileBytes.Length)
            $stream.Flush()
        } else {
            $notFound = "<h1>404 Not Found</h1><p>O arquivo $cleanPath nao foi encontrado.</p>"
            $nfBytes = [System.Text.Encoding]::UTF8.GetBytes($notFound)
            $headers = "HTTP/1.1 404 Not Found`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($nfBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($hdrBytes, 0, $hdrBytes.Length)
            $stream.Write($nfBytes, 0, $nfBytes.Length)
            $stream.Flush()
        }
        
        $client.Close()
    } catch {
        try { $client.Close() } catch {}
    }
}
