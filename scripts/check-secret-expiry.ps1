$WarningDays = 30
$HighDays = 14
$CriticalDays = 7

Write-Host ""
Write-Host "Secret Expiry Report"
Write-Host "===================="
Write-Host ""

# Get all Kubernetes secrets from all namespaces
$secretsJson = kubectl get secrets -A -o json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Unable to retrieve Kubernetes secrets."
    exit 1
}

$secrets = $secretsJson | ConvertFrom-Json

$results = @()

# Check every secret
foreach ($secret in $secrets.items) {

    # Read the custom expiry-date annotation
    $expiryDateText = $secret.metadata.annotations.'expiry-date'

    # Skip secrets that do not have an expiry date
    if (-not $expiryDateText) {
        continue
    }

    try {
        $namespace = $secret.metadata.namespace
        $name = $secret.metadata.name

        # Parse expiry date as yyyy-MM-dd
        $expiryDate = [DateTime]::ParseExact(
            $expiryDateText,
            "yyyy-MM-dd",
            [System.Globalization.CultureInfo]::InvariantCulture
        ).Date

        $today = (Get-Date).Date

        # Calculate remaining days
        $daysRemaining = [math]::Floor(
            ($expiryDate - $today).TotalDays
        )

        # Determine status
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

        # Add result to report
        $results += [PSCustomObject]@{
            Namespace     = $namespace
            Secret        = $name
            ExpiryDate    = $expiryDate.ToString("yyyy-MM-dd")
            DaysRemaining = $daysRemaining
            Status        = $status
        }
    }
    catch {
        Write-Warning "Could not process expiry date for $($secret.metadata.namespace)/$($secret.metadata.name)"
    }
}

# Sort secrets by expiry
$results = $results | Sort-Object DaysRemaining

# Display detailed report
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary"
Write-Host "======="

# Count secrets by status
$healthy  = @($results | Where-Object Status -eq "HEALTHY").Count
$warning  = @($results | Where-Object Status -eq "WARNING").Count
$high     = @($results | Where-Object Status -eq "HIGH").Count
$critical = @($results | Where-Object Status -eq "CRITICAL").Count
$expired  = @($results | Where-Object Status -eq "EXPIRED").Count

Write-Host "Healthy  : $healthy"
Write-Host "Warning  : $warning"
Write-Host "High     : $high"
Write-Host "Critical : $critical"
Write-Host "Expired  : $expired"
Write-Host ""

# Determine whether GitHub Actions should send an alert
$needsAlert = $false

if ($expired -gt 0 -or $critical -gt 0 -or $high -gt 0 -or $warning -gt 0) {
    $needsAlert = $true
}

# Pass result to GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "needs_alert=$($needsAlert.ToString().ToLower())" >> $env:GITHUB_OUTPUT
}

# Fail workflow for expired secrets
if ($expired -gt 0) {
    Write-Error "FAILED: One or more secrets are expired."
    exit 1
}

# Fail workflow for critical secrets
if ($critical -gt 0) {
    Write-Error "FAILED: One or more secrets expire within $CriticalDays days."
    exit 1
}

# Warn for HIGH or WARNING status
if ($high -gt 0 -or $warning -gt 0) {
    Write-Warning "One or more secrets require attention."
}

Write-Host "PASS: No expired or critical secrets found."
exit 0