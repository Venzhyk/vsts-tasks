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

    $manualEnvironments = Get-SuspendedEnvironments $endpoint $releaseDefinitionId $releaseDefinitionEnvironment
    $getArtifactsUrl = "$($endpoint.url)_apis/Release/artifacts/versions?releaseDefinitionId=$releaseDefinitionId"
    $createReleaseUrl = "$($endpoint.url)_apis/release/releases?api-version=4.1-preview"


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
