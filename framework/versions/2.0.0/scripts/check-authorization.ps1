[CmdletBinding(DefaultParameterSetName='TASK')]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$ObservedActor,

    [Parameter(Mandatory = $true,ParameterSetName='TASK')]
    [string]$ObservedTaskId,

    [Parameter(Mandatory = $true,ParameterSetName='PROJECT_WORK')]
    [string]$RequestContextJson,

    [Parameter(Mandatory = $true)]
    [string]$ObservedOwner,

    [Parameter(Mandatory = $true)]
    [ValidateSet('NONE','CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')]
    [string[]]$ObservedAction,

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedPath,

    [string[]]$ObservedIdentity = @(),

    [string]$ControllerControlPath,

    [string]$ObservedRepositoryId,

    [string]$ProjectConfigPath,

    [string]$ExpectedProjectConfigIdentity,

    [Parameter(ParameterSetName='TASK')]
    [string]$TaskPath,

    [Parameter(ParameterSetName='TASK')]
    [string]$ExpectedTaskIdentity,

    [string]$ContinuationReceiptPath,

    [string]$ExpectedContinuationReceiptIdentity,

    [string]$ControlRoot,

    [string[]]$ForbiddenPaths=@(),

    [string[]]$ProtectedPaths=@(),

    [switch]$RootRepositoryBindingValidated
)
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}
Import-Module (Join-Path $PSScriptRoot 'AuthorizationCheck.psm1')
$response=Invoke-AiwAuthorizationCheck @PSBoundParameters
$response.output | Write-Output
exit $response.exitCode
