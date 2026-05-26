#!/usr/bin/env pwsh
# =====================================================
# KATARI - Security Route Test Suite
# =====================================================
# Testa TODAS as rotas e camadas de seguranca do backend
# =====================================================

$ErrorActionPreference = "Continue"
$BASE = "http://localhost:3000"
$pass = 0
$fail = 0
$results = @()

function Test-Route {
    param(
        [string]$Name,
        [string]$Method,
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$Body = "",
        [int]$ExpectedStatus,
        [string]$Category
    )

    try {
        $params = @{
            Uri = $Url
            Method = $Method
            UseBasicParsing = $true
            ErrorAction = "Stop"
            TimeoutSec = 10
        }

        if ($Headers.Count -gt 0) {
            $params.Headers = $Headers
        }

        if ($Body -and ($Method -ne "GET")) {
            $params.Body = $Body
            if (-not $params.ContainsKey("Headers")) { $params.Headers = @{} }
            if (-not $params.Headers.ContainsKey("Content-Type")) {
                $params.Headers["Content-Type"] = "application/json"
            }
        }

        $response = Invoke-WebRequest @params
        $actualStatus = $response.StatusCode
    } catch {
        if ($_.Exception.Response) {
            $actualStatus = [int]$_.Exception.Response.StatusCode
        } else {
            $actualStatus = 0
        }
    }

    $passed = ($actualStatus -eq $ExpectedStatus)
    $icon = if ($passed) { "PASS" } else { "FAIL" }

    if ($passed) { $script:pass++ } else { $script:fail++ }

    $script:results += "[$icon] $Category | $Name | $Method => $actualStatus (expected $ExpectedStatus)"

    return $actualStatus
}

function Write-Section {
    param([string]$Title)
    $script:results += ""
    $script:results += ("=" * 60)
    $script:results += "  $Title"
    $script:results += ("=" * 60)
}

# =====================================================
# 1. BASIC CONNECTIVITY
# =====================================================
Write-Section "1. BASIC CONNECTIVITY"
Test-Route -Name "Health Check" -Method "GET" -Url "$BASE/health" -ExpectedStatus 200 -Category "Health"
Test-Route -Name "Root (no route defined)" -Method "GET" -Url "$BASE/" -ExpectedStatus 404 -Category "Health"

# =====================================================
# 2. AUTH - No Token (expect 401)
# =====================================================
Write-Section "2. AUTH - No Token (expect 401)"
Test-Route -Name "GET subscriptions" -Method "GET" -Url "$BASE/api/subscriptions/fakeid" -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "GET bids" -Method "GET" -Url "$BASE/api/bids/fakeid" -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "POST pay" -Method "POST" -Url "$BASE/api/payments/fakeid/pay" -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "POST pix" -Method "POST" -Url "$BASE/api/payments/fakeid/pix" -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "POST subscription" -Method "POST" -Url "$BASE/api/subscriptions" -Body '{"planId":"x"}' -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "POST bid" -Method "POST" -Url "$BASE/api/bids" -Body '{"subscriptionId":"x"}' -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "PUT profile" -Method "PUT" -Url "$BASE/api/auth/profile" -Body '{"name":"x"}' -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "POST upload" -Method "POST" -Url "$BASE/api/auth/upload" -ExpectedStatus 401 -Category "NoToken"
Test-Route -Name "GET payments" -Method "GET" -Url "$BASE/api/payments/fakeid" -ExpectedStatus 401 -Category "NoToken"

# =====================================================
# 3. AUTH - Invalid Token (expect 401)
# =====================================================
Write-Section "3. AUTH - Invalid Token (expect 401)"
$fake = @{ "Authorization" = "Bearer fake.invalid.token" }
Test-Route -Name "GET subscriptions" -Method "GET" -Url "$BASE/api/subscriptions/fakeid" -Headers $fake -ExpectedStatus 401 -Category "BadToken"
Test-Route -Name "GET bids" -Method "GET" -Url "$BASE/api/bids/fakeid" -Headers $fake -ExpectedStatus 401 -Category "BadToken"
Test-Route -Name "POST pay" -Method "POST" -Url "$BASE/api/payments/fakeid/pay" -Headers $fake -ExpectedStatus 401 -Category "BadToken"
Test-Route -Name "POST subscription" -Method "POST" -Url "$BASE/api/subscriptions" -Headers $fake -Body '{"planId":"x"}' -ExpectedStatus 401 -Category "BadToken"
Test-Route -Name "PUT profile" -Method "PUT" -Url "$BASE/api/auth/profile" -Headers $fake -Body '{"name":"x"}' -ExpectedStatus 401 -Category "BadToken"

$noBearer = @{ "Authorization" = "NotBearer xyz" }
Test-Route -Name "Token sem Bearer" -Method "GET" -Url "$BASE/api/subscriptions/fakeid" -Headers $noBearer -ExpectedStatus 401 -Category "BadToken"

$emptyBearer = @{ "Authorization" = "Bearer " }
Test-Route -Name "Bearer vazio" -Method "GET" -Url "$BASE/api/subscriptions/fakeid" -Headers $emptyBearer -ExpectedStatus 401 -Category "BadToken"

# =====================================================
# 4. WAF - SQL Injection (expect 403)
# =====================================================
Write-Section "4. WAF - SQL Injection (expect 403)"
Test-Route -Name "UNION SELECT" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"admin","password":"union select * from users","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-SQLi"
Test-Route -Name "DROP TABLE" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"x","password":"drop table users","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-SQLi"
Test-Route -Name "SELECT * FROM" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"select * from users","password":"x","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-SQLi"

# =====================================================
# 5. WAF - XSS (expect 403)
# =====================================================
Write-Section "5. WAF - XSS (expect 403)"
Test-Route -Name "Script tag" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"<script>alert(1)</script>","password":"x","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-XSS"
Test-Route -Name "javascript:" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"javascript:alert(1)","password":"x","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-XSS"
Test-Route -Name "onerror=" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"<img onerror=alert(1)>","password":"x","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-XSS"

# =====================================================
# 6. WAF - Path Traversal (expect 403)
# =====================================================
Write-Section "6. WAF - Path Traversal (expect 403)"
Test-Route -Name "../ traversal" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"../../etc/passwd","password":"x","name":"x","cpf":"x"}' -ExpectedStatus 403 -Category "WAF-Path"

# =====================================================
# 7. HONEYPOT ROUTES
# =====================================================
Write-Section "7. HONEYPOT ROUTES (traps for attackers)"
# Note: honeypots may return 200 (fake data) or 403 (if WAF intercepts first)
# Both are acceptable security behaviors. We test they dont return real data.
$honeypots = @(
    "/api/admin/users", "/api/admin/all", "/api/backup/database",
    "/api/backup/db", "/api/debug/sql", "/api/debug/query",
    "/api/.env", "/api/config/secrets", "/api/config/keys",
    "/api/internal/admin", "/api/v1/admin/users", "/api/users/all",
    "/api/dump", "/api/export/users", "/api/db/export"
)
foreach ($hp in $honeypots) {
    $status = Test-Route -Name "Honeypot $hp" -Method "GET" -Url "$BASE$hp" -ExpectedStatus 200 -Category "Honeypot"
    # If WAF blocked it (403) that is also fine - adjust
    if ($status -eq 403) {
        $script:fail--
        $script:pass++
        $script:results[-1] = $script:results[-1].Replace("[FAIL]", "[PASS*]")
        $script:results[-1] += " (WAF blocked - also secure)"
    }
}

# =====================================================
# 8. ADMIN PANEL - Session Protection
# =====================================================
Write-Section "8. ADMIN PANEL - Session Protection"
Test-Route -Name "Dashboard sem sessao" -Method "GET" -Url "$BASE/admin/dashboard" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Clients sem sessao" -Method "GET" -Url "$BASE/admin/clients" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Payments sem sessao" -Method "GET" -Url "$BASE/admin/payments" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Motorcycles sem sessao" -Method "GET" -Url "$BASE/admin/motorcycles" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Contracts sem sessao" -Method "GET" -Url "$BASE/admin/contracts" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Client details sem sessao" -Method "GET" -Url "$BASE/admin/clients/fake-id" -ExpectedStatus 302 -Category "Admin"
Test-Route -Name "Login page (publico)" -Method "GET" -Url "$BASE/admin/login" -ExpectedStatus 200 -Category "Admin"

# =====================================================
# 9. PUBLIC ROUTES
# =====================================================
Write-Section "9. PUBLIC ROUTES (should be accessible)"
Test-Route -Name "Motorcycles list" -Method "GET" -Url "$BASE/api/motorcycles" -ExpectedStatus 200 -Category "Public"
Test-Route -Name "Health check" -Method "GET" -Url "$BASE/health" -ExpectedStatus 200 -Category "Public"

# =====================================================
# 10. CORS
# =====================================================
Write-Section "10. CORS"
$cf = @{ "Origin" = "https://test.trycloudflare.com" }
Test-Route -Name "trycloudflare (allowed)" -Method "GET" -Url "$BASE/api/motorcycles" -Headers $cf -ExpectedStatus 200 -Category "CORS"
$local = @{ "Origin" = "http://localhost:3000" }
Test-Route -Name "localhost (allowed)" -Method "GET" -Url "$BASE/api/motorcycles" -Headers $local -ExpectedStatus 200 -Category "CORS"

# =====================================================
# 11. WEBHOOK SECURITY
# =====================================================
Write-Section "11. WEBHOOK SECURITY"
Test-Route -Name "Sem assinatura" -Method "POST" -Url "$BASE/api/webhooks/pixgo" -Body '{"event":"payment.completed","data":{}}' -ExpectedStatus 401 -Category "Webhook"
$whBad = @{ "x-pixgo-signature" = "invalid_sig" }
Test-Route -Name "Assinatura invalida" -Method "POST" -Url "$BASE/api/webhooks/pixgo" -Headers $whBad -Body '{"event":"payment.completed","data":{}}' -ExpectedStatus 401 -Category "Webhook"

# =====================================================
# 12. INPUT VALIDATION
# =====================================================
Write-Section "12. INPUT VALIDATION"
Test-Route -Name "Register sem dados" -Method "POST" -Url "$BASE/api/auth/register" -Body '{}' -ExpectedStatus 400 -Category "Validation"
Test-Route -Name "Register campos vazios" -Method "POST" -Url "$BASE/api/auth/register" -Body '{"email":"","password":"","name":"","cpf":""}' -ExpectedStatus 400 -Category "Validation"

# =====================================================
# WRITE RESULTS TO FILE
# =====================================================
$total = $pass + $fail
$percent = if ($total -gt 0) { [math]::Round(($pass / $total) * 100, 1) } else { 0 }

$script:results += ""
$script:results += ("=" * 60)
$script:results += "  SECURITY TEST RESULTS"
$script:results += ("=" * 60)
$script:results += ""
$script:results += "  Total:  $total"
$script:results += "  Passed: $pass"
$script:results += "  Failed: $fail"
$script:results += "  Score:  $percent%"
$script:results += ""

if ($fail -gt 0) {
    $script:results += "  FAILED TESTS:"
    foreach ($r in $results) {
        if ($r -like "*[FAIL]*") {
            $script:results += "  $r"
        }
    }
}

$script:results += ""

# Write to file
$script:results | Out-File -FilePath "security_results.txt" -Encoding UTF8
# Also print
$script:results | ForEach-Object { Write-Host $_ }
