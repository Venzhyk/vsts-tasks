[CmdletBinding()]
param()

    . (Join-Path $PSScriptRoot utils.ps1)

    Trace-VstsEnteringInvocation $MyInvocation

    $releaseDescription = Get-VstsInput -Name releaseDescription
    $releaseDescription = if($releaseDescription) { $releaseDescription } else { "Created by REST API Call" }

    $releaseDefinitionId = Get-VstsInput -Name LinkedReleaseDefinition -Require
    $releaseDefinitionEnvironment = Get-VstsInput -Name LinkedReleaseDefinitionEnvironment -Require

    $useLatestArtifacts = (Get-VstsInput -Name ArtifactsSource -Require) -eq "useLatest"
    
    $isDraft = Get-VstsInput -Name isDraft -Require
    $endpoint = Get-EndPoint LinkedReleaseDefinitionVSTSConnectedServiceName 
    $authHeader = Get-AuthHeaderValue $endpoint

    $waitForEnd = (Get-VstsInput -Name waitForLinkedRelease) -eq "true"
    $waitTimeout = [int] (Get-VstsInput -Name LinkedReleaseWaitTimeout)
    $slidingTimeout = (Get-VstsInput -Name slidingTimeoutForLinkedRelease) -eq "true"

    $manualEnvironments = Get-SuspendedEnvironments $endpoint $releaseDefinitionId $releaseDefinitionEnvironment
    $getArtifactsUrl = "$($endpoint.url)_apis/Release/artifacts/versions?releaseDefinitionId=$releaseDefinitionId"
    $createReleaseUrl = "$($endpoint.url)_apis/release/releases?api-version=4.1-preview"
    $getReleaseEnvironment = "$($endpoint.url)_apis/Release/releases/{0}/environments/{1}?api-version=4.1-preview.5"

    try {
        "-----------------------------------------------------------------"
        "Get lastes artifacts for release definition #$releaseDefinitionId"
        "About to send request: $getArtifactsUrl" 
        $result = Invoke-WebRequest -Method Get -Uri $getArtifactsUrl -ContentType "application/json" -Headers @{Authorization=$authHeader}
        $result
        $json = ConvertFrom-Json $result.Content
        $artifacts = $json.artifactVersions | Select-Object -Property alias, @{ Name='defaultVersion'; Expression={$_.defaultVersion.id}}

        "-----------------------------------------------------------------"
        Write-Host "Artifacts retrived:"
        $artifacts
    } catch {
        Write-Host $_.Exception;
        Write-Error "Cannot get release definition artifacts"
    }

    "-----------------------------------------------------------------"
    "Prepare New Release Request body"

    $artifactFormat = @"
        {{
            "alias": "{0}",
            "instanceReference": {{
            "id": {1},
            "name": null
            }}
        }},
"@
$acc = ""
if ($useLatestArtifacts) {
    "Use latest artifacts"
    $($artifacts | ForEach-Object -Process {$acc = $acc + ($artifactFormat -f $_.alias, $_.defaultVersion)})
} else {
    
    "Use binded artifacts from current release"
    $artifactNames =  $artifacts | Select-Object -ExpandProperty alias

    # get all artifacts of current release definition
    $thisReleaseArtifacts = (Get-VstsTaskVariableInfo | Where-Object { $_.Name.StartsWith("RELEASE.ARTIFACTS.","CurrentCultureIgnoreCase") -and $_.Name.EndsWith(".BUILDID", "CurrentCultureIgnoreCase")})
                                                                                                                                                                # if you trim end ".buildId", it will also trim last char before dot
                                                                                                                                                                # therefore, we trim tailing dot with separate method call
    $thisReleaseArtifacts = $thisReleaseArtifacts | Select-Object -Property @{ Name='alias'; Expression={$_.Name.TrimStart("release.artifacts.").TrimEnd("buildId").TrimEnd(".")}}, Value
    # fitler artifacts that are not exist in target release definition
    $thisReleaseArtifacts = $thisReleaseArtifacts | Where-Object { $artifactNames.Contains($_.alias) }

    $($thisReleaseArtifacts | ForEach-Object -Process { $acc = $acc + ($artifactFormat -f $_.alias, $_.Value) })

    if ($artifacts.Count -gt $thisReleaseArtifacts.Count) {
        
        $existingArtifactNames = $thisReleaseArtifacts | Select-Object -ExpandProperty alias
        $missedArtifacts = $artifacts | Where-Object { -not $existingArtifactNames.Contains($_.alias) } | Select-Object -ExpandProperty alias

        "Missed artifacts: "
        $missedArtifacts
        Write-Error "Ensure that your release definition contains all artifacts for linked release. Check list above"
    }
    
}

$body= @"
{
"definitionId": $releaseDefinitionId,
"description": "$releaseDescription",
"isDraft": $isDraft,
"manualEnvironments": [$manualEnvironments],
"reason": "none",
    "artifacts": [
$acc
    ]
}
"@

    try {
        "-----------------------------------------------------------------"
        "Create new release from definition #$releaseDefinitionId"
        "About to send request: $createReleaseUrl"
        "Request body: "
        $body

        $newRelease = Invoke-WebRequest -Method Post -Uri $createReleaseUrl -ContentType "application/json" -Headers @{Authorization=$authHeader} -Body $body

    } catch {
        if (-not $useLatestArtifacts) {
            Write-Warning "Ensure that your release has following artifacts:"
            $existingArtifactNames = $thisReleaseArtifacts | Select-Object -ExpandProperty alias
            $artifacts | Where-Object { -not $existingArtifactNames.Contains($_.alias) } | Select-Object -ExpandProperty alias
        }
       Write-Error $_.Exception
    }

    "-----------------------------------------------------------------"
    if($newRelease.StatusCode -ne 200){
        $newRelease
        (ConvertFrom-Json $newRelease.Content)
        Write-Error  "Request failed"
    }
    else {
        Write-Host "Release successfully created"
    }

    "Request response:"
    $newRelease

    if ($waitForEnd -eq $True) {
        "Wait for linked release..."

        $json = ConvertFrom-Json $newRelease.Content
        $releaseId = $json.id
        $envId = $json.environments | Where-Object { $_.name -eq $releaseDefinitionEnvironment }  | Select-Object -ExpandProperty id

        $url = $getReleaseEnvironment -f $releaseId, $envId        
        "Linked Release details: $url"

        $attempt = 0
        $failAfter = [DateTime]::Now.AddMinutes($waitTimeout)

        while ($failAfter -gt [DateTime]::Now) {
            $delay = ExponentialDelay $attempt ($waitTimeout * 60  / 2d )
            $attempt++
            Start-Sleep -s $delay
            "Check release status $attempt..."

            $result = Invoke-WebRequest -Method Get -Uri $url -ContentType "application/json" -Headers @{Authorization=$authHeader}
            $status = (ConvertFrom-Json $result.Content).status

            $status
            if ($status -eq 'succeeded') {
                return 0
            } 
            if ($status -eq 'inProgress' -and $slidingTimeout) {
                $waitTimeout = $waitTimeout * 2
                $failAfter = $failAfter.AddMinutes($waitTimeout)
            }
            if($status -eq 'failed') {
                Write-Error "Linked Release failed"
            }
            if($status -eq 'canceled') {
                Write-Error "Linked Release canceled"
            }
        }
        Write-Error "Failed by timeout ($waitTimeout mins)"

    } 
    "... end"
