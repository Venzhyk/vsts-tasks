function Get-EndPoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$connectedServiceName
        )

    $connectedService = Get-VstsInput -Name $connectedServiceName -Require
    $endpoint = Get-VstsEndpoint -Name $connectedService -Require

    $endpoint
}

function Get-AuthHeaderValue {
    param(
        $endpoint
    )

    $username = ""
    $password = [string]$endpoint.auth.parameters.password

    $basicAuth = ("{0}:{1}" -f $username, $password)
    $basicAuth = [System.Text.Encoding]::UTF8.GetBytes($basicAuth)
    $basicAuth = [System.Convert]::ToBase64String($basicAuth)
    ("Basic {0}" -f $basicAuth)
}

function Get-SuspendedEnvironments {
    param(
        $endpoint,
        $releaseDefinitionId,
        [string] $envName
    )

    if([String]::IsNullOrEmpty($envName)) {
        return ""
    }

    $authHeader = Get-AuthHeaderValue $endpoint
    
    $getReleaseEnvsri = "$($endpoint.url)_apis/release/definitions/$releaseDefinitionId"

    $result = Invoke-WebRequest -Method Get -Uri $getReleaseEnvsri -ContentType "application/json" -Headers @{Authorization=$authHeader}
    $envs = (ConvertFrom-Json $result.Content).environments | Select-Object -ExpandProperty Name 

    if (-not $envs.Contains($envName)) {
        Write-Error "Release Definition #$releaseDefinitionId doesn't contain ""$envName"" environment"
    }
    
    $envs = $envs | Where-Object { $_ -ne $envName }

    $skip = """" + [String]::Join(""",""", $envs) + """"
    Write-Host "Environments triger will be changed from automated to manual: "
    Write-Host $skip
    return $skip
}



function ExponentialDelay {
    param(
        $failedAttempts,
        $maxDelayInSeconds = 1024
        )

    # //Attempt 1     0s     0s
    # //Attempt 2     2s     2s
    # //Attempt 3     4s     4s
    # //Attempt 4     8s     8s
    # //Attempt 5     16s    16s
    # //Attempt 6     32s    32s

    # //Attempt 7     64s     1m 4s
    # //Attempt 8     128s    2m 8s
    # //Attempt 9     256s    4m 16s
    # //Attempt 10    512     8m 32s
    # //Attempt 11    1024    17m 4s
    # //Attempt 12    2048    34m 8s

    # //Attempt 13    4096    1h 8m 16s
    # //Attempt 14    8192    2h 16m 32s
    # //Attempt 15    16384   4h 33m 4s

    $delayInSeconds = ((1d / 2d) * ([Math]::Pow(2d, $failedAttempts) - 1d))

    if($maxDelayInSeconds -lt $delayInSeconds){
        $maxDelayInSeconds
    } else {
        $delayInSeconds
    }
}