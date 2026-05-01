# ============================================================
# Combined Network + Proxy Diagnostic Suite (ASCII Safe)
# ============================================================

$Target = "nwrprod.service-now.com"
$Url = "https://$Target/oauth_token.do"

Write-Host "=== Combined Network and Proxy Diagnostic Suite ==="
Write-Host "Target: $Url"
Write-Host ""

# ============================================================
# 1. Full Network Diagnostic
# ============================================================

Write-Host "=== Network Diagnostic ==="

# DNS
Write-Host ""
Write-Host "DNS Resolution..."
try {
    Resolve-DnsName $Target -ErrorAction Stop | Out-String | Write-Host
    $DnsOK = $true
} catch {
    Write-Host "DNS failed: $($_.Exception.Message)"
    $DnsOK = $false
}

# Ping
Write-Host ""
Write-Host "ICMP Ping..."
try {
    Test-Connection -ComputerName $Target -Count 4 -ErrorAction Stop | Out-String | Write-Host
    $PingOK = $true
} catch {
    Write-Host "Ping failed: $($_.Exception.Message)"
    $PingOK = $false
}

# Trace Route
Write-Host ""
Write-Host "Trace Route..."
try {
    $trace = Test-NetConnection -ComputerName $Target -TraceRoute
    $trace | Out-String | Write-Host
    $TraceOK = $true
} catch {
    Write-Host "TraceRoute failed: $($_.Exception.Message)"
    $TraceOK = $false
}

# Port Test
Write-Host ""
Write-Host "TCP Port Test (443)..."
try {
    $port = Test-NetConnection -ComputerName $Target -Port 443
    $port | Out-String | Write-Host
    $PortOK = $port.TcpTestSucceeded
} catch {
    Write-Host "Port test failed: $($_.Exception.Message)"
    $PortOK = $false
}

# HTTPS Test
Write-Host ""
Write-Host "HTTPS Test..."
try {
    Invoke-WebRequest -Uri "https://$Target" -TimeoutSec 10 -ErrorAction Stop |
        Select-Object StatusCode, StatusDescription, Headers |
        Out-String | Write-Host
    $HttpOK = $true
} catch {
    Write-Host "HTTPS failed: $($_.Exception.Message)"
    $HttpOK = $false
}

# Proxy
Write-Host ""
Write-Host "WinHTTP Proxy Settings..."
$proxy = netsh winhttp show proxy
$proxy | Out-String | Write-Host

# Local Network
Write-Host ""
Write-Host "Local Network Configuration..."
ipconfig /all | Out-String | Write-Host

# Routing Table
Write-Host ""
Write-Host "Routing Table..."
route print | Out-String | Write-Host

# Firewall
Write-Host ""
Write-Host "Windows Firewall State..."
Get-NetFirewallProfile | Out-String | Write-Host

# ============================================================
# 2. Proxy / SSL Inspection Fingerprinting
# ============================================================

Write-Host ""
Write-Host "=== Proxy and SSL Inspection Diagnostic ==="

function Test-Method {
    param($Method)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method $Method -TimeoutSec 10 -ErrorAction Stop
        return @{ Success = $true; Status = $resp.StatusCode }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "Testing HTTP Methods..."
$GetTest  = Test-Method -Method "GET"
$PostTest = Test-Method -Method "POST"

Write-Host "GET:"
$GetTest | Out-String | Write-Host

Write-Host "POST:"
$PostTest | Out-String | Write-Host

# Certificate Extraction
Write-Host ""
Write-Host "Extracting TLS Certificate..."

try {
    $tcp = New-Object System.Net.Sockets.TcpClient($Target, 443)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
    $ssl.AuthenticateAsClient($Target)

    $cert = $ssl.RemoteCertificate
    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

    Write-Host ""
    Write-Host "Subject: $($cert2.Subject)"
    Write-Host "Issuer : $($cert2.Issuer)"
    Write-Host "Thumb  : $($cert2.Thumbprint)"
    Write-Host "Valid  : $($cert2.NotBefore) to $($cert2.NotAfter)"
    Write-Host "TLS    : $($ssl.SslProtocol)"
}
catch {
    Write-Host "Certificate extraction failed: $($_.Exception.Message)"
}

$issuer = $cert2.Issuer

# Proxy Vendor Fingerprint
Write-Host ""
Write-Host "Proxy Vendor Fingerprint..."

switch -Wildcard ($issuer) {
    "*Zscaler*"        { Write-Host "Detected: Zscaler"; break }
    "*Blue Coat*"      { Write-Host "Detected: Blue Coat / Symantec"; break }
    "*Forcepoint*"     { Write-Host "Detected: Forcepoint"; break }
    "*Palo Alto*"      { Write-Host "Detected: Palo Alto"; break }
    "*Cisco*"          { Write-Host "Detected: Cisco"; break }
    "*Sophos*"         { Write-Host "Detected: Sophos"; break }
    "*Netskope*"       { Write-Host "Detected: Netskope"; break }
    "*McAfee*"         { Write-Host "Detected: McAfee"; break }
    "*Fortinet*"       { Write-Host "Detected: Fortinet"; break }
    default            { Write-Host "No known proxy fingerprint detected." }
}

# Header Integrity Test
Write-Host ""
Write-Host "Testing Header Integrity..."

try {
    $headers = @{ "X-Diag-Test" = "12345" }
    $resp = Invoke-WebRequest -Uri $Url -Method GET -Headers $headers -TimeoutSec 10 -ErrorAction Stop

    if ($resp.RawContent -match "12345") {
        Write-Host "Header preserved"
    } else {
        Write-Host "Header stripped or rewritten"
    }
}
catch {
    Write-Host "Header test failed: $($_.Exception.Message)"
}

# ============================================================
# 3. User-Friendly Summary
# ============================================================

Write-Host ""
Write-Host "=== USER-FRIENDLY RESULT SUMMARY ==="

if ($PostTest.Success -eq $false -and $PostTest.Error -match "401") {
    $Likely = "ServiceNow OAuth endpoint rejected the request (401 Unauthorized)"
    $Where  = "Application Layer (ServiceNow)"
    $Why    = "Missing or invalid OAuth parameters or credentials"
}
elseif ($issuer -notmatch "DigiCert") {
    $Likely = "SSL inspection or MITM detected"
    $Where  = "Corporate Proxy or SSL Inspection Appliance"
    $Why    = "Certificate issuer does not match DigiCert"
}
elseif ($GetTest.Success -eq $false -and $PostTest.Success -eq $false) {
    $Likely = "HTTPS traffic blocked or timing out"
    $Where  = "Network Edge, Firewall, or Transparent Proxy"
    $Why    = "GET and POST both failed"
}
else {
    $Likely = "Mixed or unclear signals"
    $Where  = "Unknown"
    $Why    = "Further testing required"
}

Write-Host ""
Write-Host "LIKELY ROOT CAUSE:"
Write-Host "  $Likely"

Write-Host ""
Write-Host "WHERE THE BLOCK OCCURS:"
Write-Host "  $Where"

Write-Host ""
Write-Host "WHY THIS IS LIKELY:"
Write-Host "  $Why"

Write-Host ""
Write-Host "NETWORK HEALTH CHECK:"

if ($issuer -match "DigiCert") {
    Write-Host "  OK: SSL certificate is genuine"
} else {
    Write-Host "  FAIL: SSL certificate is not genuine"
}

if ($ssl.SslProtocol -match "Tls12|Tls13") {
    Write-Host "  OK: TLS version is modern"
} else {
    Write-Host "  FAIL: TLS downgrade detected"
}

if ($proxy -match "Direct access") {
    Write-Host "  OK: No explicit proxy configured"
} else {
    Write-Host "  FAIL: Explicit proxy detected"
}

Write-Host ""
Write-Host "=== END OF SUMMARY ==="
Write-Host ""
Write-Host "Diagnostic complete."
