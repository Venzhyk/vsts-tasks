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
