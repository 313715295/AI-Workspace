Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop

function New-AiwBootstrapFormatProjection {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$TargetVersionRoot,[string[]]$ForbiddenPaths=@(),$SourceProjection=$null)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $formatModule=@(Import-Module (Join-Path $TargetVersionRoot 'scripts/ObjectFormats.psm1') -PassThru -ErrorAction Stop)[0]
    $formatReader=$formatModule.ExportedCommands['Read-AiwCurrentObject']
    $configPath=Get-AiwContainedPath $root '.ai-workspace/project.json';$config=Read-AiwProjectionFormatObject -Root $root -Relative '.ai-workspace/project.json' -Projection $SourceProjection -Label 'FORMAT_PROJECT'
    $policyPath=Get-AiwContainedPath $root '.ai-workspace/process-policy.json';$policy=Read-AiwProjectionFormatObject -Root $root -Relative '.ai-workspace/process-policy.json' -Projection $SourceProjection -Label 'FORMAT_POLICY'
    $correctionPath=Get-AiwContainedPath $root '.ai-workspace/corrections.json';$corrections=Read-AiwProjectionFormatObject -Root $root -Relative '.ai-workspace/corrections.json' -Projection $SourceProjection -Label 'FORMAT_CORRECTIONS'
    $profile=(Read-AiwProjectJson (Join-Path $TargetVersionRoot 'ADOPTION_PROFILE.json') 'ADOPTION_PROFILE').Value
    $null=Assert-AiwFormatAdoptionProfile $profile $TargetVersionRoot $profile.frameworkVersion
    $context=[pscustomobject]@{ProjectId=$config.Value.id;LibraryId='project-knowledge';LegacyPolicy=$policy.Value;ForbiddenPaths=@($ForbiddenPaths);TargetProcessContractVersion=$profile.projectControl.processCarrierContractVersion}
    $project=Read-AiwProjectionFormatObject -Root $root -Relative '.ai-workspace/project.json' -Projection $SourceProjection -ObjectType PROJECT_CONFIG -Context $context -Label 'FORMAT_CONFIG' -CurrentObjectReader $formatReader
    $context|Add-Member SourceBindings @($project.Value.sourceBindings)
    $newPolicy=Read-AiwProjectionFormatObject -Root $root -Relative '.ai-workspace/process-policy.json' -Projection $SourceProjection -ObjectType PROCESS_POLICY -Context $context -Label 'FORMAT_POLICY' -CurrentObjectReader $formatReader
    $newCorrections=Read-AiwAdoptionCorrectionsFormatObject -Root $root -Projection $SourceProjection -Context $context -TargetVersionRoot $TargetVersionRoot
    $targets=@([pscustomobject]@{path='.ai-workspace/project.json';bytes=$project.CurrentBytes},[pscustomobject]@{path='.ai-workspace/process-policy.json';bytes=$newPolicy.CurrentBytes},[pscustomobject]@{path='.ai-workspace/corrections.json';bytes=$newCorrections.CurrentBytes})
    $formats=@($project,$newPolicy,$newCorrections)
    # Only the explicitly declared, project-owned legacy index can join the
    # bootstrap write group. Shared/external indexes keep their original bytes.
    if($config.Value.schemaVersion-eq4-and$null-ne$config.Value.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']-and$null-ne$config.Value.frameworkCapabilities.KNOWLEDGE_REFERENCE.PSObject.Properties['indexLocator']){
        $indexRelative=$config.Value.frameworkCapabilities.KNOWLEDGE_REFERENCE.indexLocator
        Assert-AiwRelativePath $indexRelative
        $indexPath=[IO.Path]::GetFullPath((Join-Path $root $indexRelative))
        foreach($scope in @($ForbiddenPaths)+@($config.Value.routineExcludedPaths)){
            $absolute=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($scope)){$scope}else{Join-Path $root $scope}))
            if($indexPath.Equals($absolute,[StringComparison]::OrdinalIgnoreCase)-or$indexPath.StartsWith($absolute.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'FORMAT_SOURCE_DENIED'}
        }
        $indexPath=Get-AiwContainedPath $root $indexRelative
        $index=Read-AiwProjectionFormatObject -Root $root -Relative $indexRelative -Projection $SourceProjection -Label 'FORMAT_INDEX'
        $converted=Read-AiwProjectionFormatObject -Root $root -Relative $indexRelative -Projection $SourceProjection -ObjectType KNOWLEDGE_INDEX -Context $context -Label 'FORMAT_INDEX' -CurrentObjectReader $formatReader
        $formats+=$converted;$targets+=[pscustomobject]@{path=$indexRelative;bytes=$converted.CurrentBytes}
    }
    return [pscustomobject]@{status='PREVIEW';projection=(New-AiwProjectProjection $root $targets);targets=$targets;project=$project.Value;policy=$newPolicy.Value;corrections=$newCorrections.Value;formats=$formats;formatWriteRequired=(@($formats|Where-Object{$_.Segments.Count}).Count-gt0);authority=$false}
}
Export-ModuleMember -Function New-AiwBootstrapFormatProjection

function Get-AiwTargetBytes {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $hasBytes = $Target.PSObject.Properties.Name -ccontains 'bytes'
    $hasText = $Target.PSObject.Properties.Name -ccontains 'text'
    if ($hasBytes -eq $hasText) {
        throw ('TARGET_CONTENT_SHAPE|' + $RelativePath)
    }
    if ($hasBytes) {
        if ($null -eq $Target.bytes) {
            throw ('TARGET_CONTENT_NULL|' + $RelativePath)
        }
        return ,([byte[]]$Target.bytes)
    }
    return ,([Text.UTF8Encoding]::new($false).GetBytes([string]$Target.text))
}

# One pure algorithm; only the exported normal consumer acquires a source scope.
# Initial registration invokes this private core in this exact module while its
# entire control directory is absent. A projection is data, never a lease.
function New-AiwProjectProjectionCore {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][object[]]$TargetObject)
    $root = Resolve-AiwRepositoryRoot $RepositoryRoot
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.List[object]]::new()

    foreach ($target in @($TargetObject)) {
        if ($null -eq $target.PSObject.Properties['path']) {
            throw 'TARGET_PATH_MISSING'
        }
        $relative = [string]$target.path
        Assert-AiwRelativePath $relative
        if (-not $seen.Add($relative)) {
            throw ('MANAGED_PATH_DUPLICATE|' + $relative)
        }

        $path = Get-AiwContainedPath $root $relative
        $kind = if ($target.PSObject.Properties.Name -ccontains 'kind') {
            [string]$target.kind
        }
        else {
            'FILE'
        }
        if ($kind -cnotin @('FILE', 'DIRECTORY')) {
            throw ('TARGET_KIND|' + $relative)
        }
        $existing = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and
            (($kind -ceq 'FILE' -and $existing.PSIsContainer) -or
             ($kind -ceq 'DIRECTORY' -and -not $existing.PSIsContainer))) {
            throw ('MANAGED_PATH_KIND_CONFLICT|' + $relative)
        }
        if ($null -ne $existing -and
            ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('MANAGED_PATH_REPARSE|' + $relative)
        }
        $oldExists = $null -ne $existing
        [byte[]]$oldBytes = [byte[]]::new(0)
        if ($oldExists -and $kind -ceq 'FILE') {
            $oldBytes = [IO.File]::ReadAllBytes($path)
        }

        $newExists = $true
        if ($target.PSObject.Properties.Name -ccontains 'exists') {
            if ($target.exists -isnot [bool]) {
                throw ('TARGET_EXISTS_NOT_BOOLEAN|' + $relative)
            }
            $newExists = [bool]$target.exists
        }

        if ($kind -ceq 'DIRECTORY' -and -not $newExists) {
            throw ('TARGET_DIRECTORY_DELETE_UNSUPPORTED|' + $relative)
        }
        [byte[]]$newBytes = [byte[]]::new(0)
        if ($newExists -and $kind -ceq 'FILE') {
            $newBytes = Get-AiwTargetBytes $target $relative
        }
        elseif ($kind -ceq 'DIRECTORY' -and
                (($target.PSObject.Properties.Name -ccontains 'bytes') -or
                 ($target.PSObject.Properties.Name -ccontains 'text'))) {
            throw ('TARGET_DIRECTORY_HAS_CONTENT|' + $relative)
        }
        elseif (($target.PSObject.Properties.Name -ccontains 'bytes') -or
                ($target.PSObject.Properties.Name -ccontains 'text')) {
            throw ('TARGET_DELETE_HAS_CONTENT|' + $relative)
        }

        $oldIdentity = if (-not $oldExists) { 'MISSING' } elseif ($kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $oldBytes }
        $newIdentity = if (-not $newExists) { 'MISSING' } elseif ($kind -ceq 'DIRECTORY') { 'DIRECTORY' } else { Get-AiwByteIdentity $newBytes }
        $objects.Add([pscustomobject]@{
            path = $relative
            kind = $kind
            oldExists = $oldExists
            newExists = $newExists
            oldIdentity = $oldIdentity
            newIdentity = $newIdentity
            changed = $oldIdentity -cne $newIdentity
            oldBase64 = [Convert]::ToBase64String($oldBytes)
            newBase64 = [Convert]::ToBase64String($newBytes)
        })
    }

    $changed = @($objects | Where-Object changed)
    [pscustomobject]@{
        schemaVersion = 1
        repositoryRoot = $root
        objects = @($objects)
        changeCount = $changed.Count
        noOp = $changed.Count -eq 0
    }
}

function New-AiwProjectProjection {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][object[]]$TargetObject)
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $RepositoryRoot -Mode OBSERVE
try {
    New-AiwProjectProjectionCore $RepositoryRoot $TargetObject
} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}

function Get-AiwProjectProjectionDiff {
    param([Parameter(Mandatory)]$Projection)

    @($Projection.objects | ForEach-Object {
        $change = if (-not $_.changed) {
            'UNCHANGED'
        }
        elseif (-not $_.newExists) {
            'DELETE'
        }
        elseif ($_.oldExists) {
            'REPLACE'
        }
        else {
            'CREATE'
        }
        [pscustomobject]@{
            path = $_.path
            kind = $_.kind
            change = $change
            oldIdentity = $_.oldIdentity
            newIdentity = $_.newIdentity
        }
    })
}

Export-ModuleMember -Function New-AiwProjectProjection, Get-AiwProjectProjectionDiff

# Read the working bytes through the existing strict object-format adapter.
# The live project remains the source root; no partial project is adopted.
function Read-AiwProjectionFormatObject {
    param([string]$Root,[string]$Relative,$Projection,[string]$Label,[string]$ObjectType,$Context,[Management.Automation.CommandInfo]$CurrentObjectReader)
    if($ObjectType-and$null-eq$CurrentObjectReader){throw 'FORMAT_CURRENT_READER_REQUIRED'}
    $live=Get-AiwContainedPath $Root $Relative
    $entries=@(if($null-ne$Projection){$Projection.objects|Where-Object path -CEQ $Relative})
    if($entries.Count-gt1){throw 'FORMAT_PROJECTED_DUPLICATE'}
    if($entries.Count-eq0){
        $doc=Read-AiwProjectJson $live $Label
        if($ObjectType){return & $CurrentObjectReader -ObjectType $ObjectType -Locator $live -ExpectedIdentity $doc.Identity -Context $Context}
        return $doc
    }
    $entry=$entries[0]
    if(-not$entry.newExists-or$entry.kind-cne'FILE'){throw 'FORMAT_REQUIRED_OBJECT_DELETED'}
    $original=if(Test-Path -LiteralPath $live -PathType Leaf){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($live))}else{'MISSING'}
    if($original-cne$entry.oldIdentity){throw 'FORMAT_PROJECTED_SOURCE_DRIFT'}
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('aiw-format-working-'+[guid]::NewGuid().ToString('N')+'.json')
    try{
        [IO.File]::WriteAllBytes($temporary,[Convert]::FromBase64String($entry.newBase64))
        $doc=Read-AiwProjectJson $temporary $Label
        if($doc.Identity-cne$entry.newIdentity){throw 'FORMAT_PROJECTED_BYTES_DRIFT'}
        if($ObjectType){
            $view=$Context|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
            $view|Add-Member ProspectiveAdoptionProjection $true -Force
            return & $CurrentObjectReader -ObjectType $ObjectType -Locator $temporary -ExpectedIdentity $doc.Identity -Context $view
        }
        return $doc
    }finally{
        $full=[IO.Path]::GetFullPath($temporary);$temp=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if([IO.Path]::GetDirectoryName($full)-cne$temp-or[IO.Path]::GetFileName($full)-cnotmatch'^aiw-format-working-[a-f0-9]{32}\.json$'){throw 'FORMAT_WORKING_CLEANUP_BOUNDARY'}
        if(Test-Path -LiteralPath $full -PathType Leaf){[IO.File]::Delete($full)}
    }
}

function Get-AiwProjectionSourceText([string]$Root,[string]$Relative,$Projection) {
# @project-source-scope
$aiwPublicationScopeLease=Enter-AiwRootProjectSourceScope -ProjectRoot $Root -Mode OBSERVE
try {

    $entries=@(if($null-ne$Projection){$Projection.objects|Where-Object path -CEQ $Relative})
    if($entries.Count-gt1){throw 'PROJECTED_SOURCE_DUPLICATE'}
    if($entries.Count-eq1){if(-not$entries[0].newExists){throw 'PROJECTED_REQUIRED_SOURCE_DELETED'};return [Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($entries[0].newBase64))}
    return [Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes((Get-AiwContainedPath $Root $Relative)))

} finally { Exit-AiwRootProjectSourceScope $aiwPublicationScopeLease }
}
Export-ModuleMember -Function Get-AiwProjectionSourceText

# The root format bridge and its saved-plan verifier use the same vocabulary
# conversion. Historical records nested in evidence remain unchanged.
function Convert-AiwAdoptionSelectors($Rules) {
    foreach($rule in @($Rules)){
        if($null-eq$rule.PSObject.Properties['selectors']){continue}
        $carriers=@($rule.selectors)
        if($null-ne$rule.selectors.PSObject.Properties['deterministicTriggers']){$carriers+=@($rule.selectors.deterministicTriggers)}
        foreach($selectors in $carriers){
            foreach($pair in @(@('roles','DOMAIN_OWNER','TASK_OWNER'),@('actionKinds','OWNER_ACCEPT','RESULT_ACCEPT'),@('resultKinds','OWNER_ACCEPTANCE','RESULT_ACCEPTANCE'))){
                if($null-ne$selectors.PSObject.Properties[$pair[0]]){
                    $selectors.($pair[0])=@($selectors.($pair[0])|ForEach-Object{if($_-ceq$pair[1]){$pair[2]}else{$_}})
                }
            }
        }
    }
}
Export-ModuleMember -Function Convert-AiwAdoptionSelectors

# Both initial preparation and saved-plan replay normalize only the current
# schema2 selector carriers before the unchanged target adapter validates them.
# The native group and its original history/effect evidence remain the source.
function Read-AiwAdoptionCorrectionsFormatObject {
    param([string]$Root,$Projection,$Context,[Parameter(Mandatory)][string]$TargetVersionRoot)
    $modulePath=[IO.Path]::GetFullPath((Join-Path $TargetVersionRoot 'scripts/ObjectFormats.psm1'))
    $formatModule=@(Import-Module $modulePath -PassThru -ErrorAction Stop)[0]
    if(-not$formatModule.Path.Equals($modulePath,[StringComparison]::OrdinalIgnoreCase)){throw 'FORMAT_TARGET_MODULE_MISMATCH'}
    $formatReader=$formatModule.ExportedCommands['Read-AiwCurrentObject']
    $working=$Projection
    $source=Read-AiwProjectionFormatObject -Root $Root -Relative '.ai-workspace/corrections.json' -Projection $Projection -Label 'FORMAT_CORRECTIONS'
    if($source.Value.schemaVersion-eq2-and$Context.TargetProcessContractVersion-ceq'2.0.0'){
        Convert-AiwAdoptionSelectors $source.Value.corrections
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($source.Value|ConvertTo-Json -Depth 100 -Compress)+"`n")
        $working=New-AiwProjectProjection $Root @([pscustomobject]@{path='.ai-workspace/corrections.json';bytes=$bytes})
    }
    return Read-AiwProjectionFormatObject -Root $Root -Relative '.ai-workspace/corrections.json' -Projection $working -ObjectType PROJECT_CORRECTIONS -Context $Context -Label 'FORMAT_CORRECTIONS' -CurrentObjectReader $formatReader
}
Export-ModuleMember -Function Read-AiwAdoptionCorrectionsFormatObject
