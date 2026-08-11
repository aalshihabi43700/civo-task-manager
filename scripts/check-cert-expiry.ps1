$WarningDays = 30
$HighDays = 14
$CriticalDays = 7

Write-Host ""
Write-Host "Certificate Expiry Report"
Write-Host "========================="
Write-Host ""

$secretsJson = kubectl get secrets -A -o json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Unable to retrieve Kubernetes secrets."
    exit 1
}

$secrets = $secretsJson | ConvertFrom-Json

$results = @()

foreach ($secret in $secrets.items) {

    if ($secret.type -ne "kubernetes.io/tls") {
        continue
    }

    $namespace = $secret.metadata.namespace
    $name = $secret.metadata.name
    $certificateData = $secret.data.'tls.crt'

    if (-not $certificateData) {
        continue
    }

    try {
        $certificateBytes = [Convert]::FromBase64String($certificateData)

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $certificateBytes
        )

        $expiryDate = $certificate.NotAfter.ToUniversalTime()
        $today = (Get-Date).ToUniversalTime()

        $daysRemaining = [math]::Floor(
            ($expiryDate - $today).TotalDays
        )

        if ($daysRemaining -lt 0) {
            $status = "EXPIRED"
        }
        elseif ($daysRemaining -le $CriticalDays) {
            $status = "CRITICAL"
        }
        elseif ($daysRemaining -le $HighDays) {
            $status = "HIGH"
        }
        elseif ($daysRemaining -le $WarningDays) {
            $status = "WARNING"
        }
        else {
            $status = "HEALTHY"
        }

        $results += [PSCustomObject]@{
            Namespace     = $namespace
            Certificate   = $name
            ExpiryDate    = $expiryDate.ToString("yyyy-MM-dd HH:mm:ss")
            DaysRemaining = $daysRemaining
            Status        = $status
        }
    }
    catch {
        Write-Warning "Could not read certificate $namespace/$name"
    }
}

$results = $results | Sort-Object DaysRemaining

$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary"
Write-Host "======="

$healthy  = ($results | Where-Object Status -eq "HEALTHY").Count
$warning  = ($results | Where-Object Status -eq "WARNING").Count
$high     = ($results | Where-Object Status -eq "HIGH").Count
$critical = ($results | Where-Object Status -eq "CRITICAL").Count
$expired  = ($results | Where-Object Status -eq "EXPIRED").Count

Write-Host "Healthy  : $healthy"
Write-Host "Warning  : $warning"
Write-Host "High     : $high"
Write-Host "Critical : $critical"
Write-Host "Expired  : $expired"
Write-Host ""

if ($expired -gt 0) {
    Write-Error "FAILED: One or more certificates are expired."
    exit 1
}

if ($critical -gt 0) {
    Write-Error "FAILED: One or more certificates expire within $CriticalDays days."
    exit 1
}

if ($high -gt 0 -or $warning -gt 0) {
    Write-Warning "Certificates require attention."
}

Write-Host "PASS: No expired or critical certificates found."
exit 0