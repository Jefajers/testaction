﻿function Invoke-AzOpsPull {

    <#
        .SYNOPSIS
            Setup a repository for the AzOps workflow, based off templates and an existing Azure deployment.
        .DESCRIPTION
            Setup a repository for the AzOps workflow, based off templates and an existing Azure deployment.
        .PARAMETER IncludeResourcesInResourceGroup
            Discover only resources in these resource groups.
        .PARAMETER IncludeResourceType
            Discover only specific resource types.
        .PARAMETER SkipChildResource
            Skip childResource discovery.
        .PARAMETER SkipPim
            Skip discovery of Privileged Identity Management resources.
        .PARAMETER SkipLock
            Skip discovery of resource lock resources.
        .PARAMETER SkipPolicy
            Skip discovery of policies.
        .PARAMETER SkipRole
            Skip discovery of role.
        .PARAMETER SkipResourceGroup
            Skip discovery of resource groups
        .PARAMETER SkipResource
            Skip discovery of resources inside resource groups.
        .PARAMETER Rebuild
            Delete all AutoGeneratedTemplateFolderPath folders inside AzOpsState directory.
        .PARAMETER Force
            Delete $script:AzOpsState directory.
        .PARAMETER StatePath
            The root folder under which to write the resource json.
        .EXAMPLE
            > Invoke-AzOpsPull
            Setup a repository for the AzOps workflow, based off templates and an existing Azure deployment.
    #>

    [CmdletBinding()]
    [Alias("Initialize-AzOpsRepository")]
    param (
        [string[]]
        $IncludeResourcesInResourceGroup = (Get-PSFConfigValue -FullName 'AzOps.Core.IncludeResourcesInResourceGroup'),

        [string[]]
        $IncludeResourceType = (Get-PSFConfigValue -FullName 'AzOps.Core.IncludeResourceType'),

        [switch]
        $SkipChildResource = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipChildResource'),

        [switch]
        $SkipPim = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipPim'),

        [switch]
        $SkipLock = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipLock'),

        [switch]
        $SkipPolicy = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipPolicy'),

        [switch]
        $SkipResource = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipResource'),

        [switch]
        $SkipResourceGroup = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipResourceGroup'),

        [string[]]
        $SkipResourceType = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipResourceType'),

        [switch]
        $SkipRole = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipRole'),

        [switch]
        $Rebuild,

        [switch]
        $Force,

        [string]
        $StatePath = (Get-PSFConfigValue -FullName 'AzOps.Core.State'),

        [string]
        $TemplateParameterFileSuffix = (Get-PSFConfigValue -FullName 'AzOps.Core.TemplateParameterFileSuffix')
    )

    begin {
        #region Prepare
        if (-not $SkipPim) {
            try {
                Write-PSFMessage -Level Verbose -String 'Invoke-AzOpsPull.Validating.UserRole'
                $null = Get-AzADUser -First 1 -ErrorAction Stop
                Write-PSFMessage -Level Verbose -String 'Invoke-AzOpsPull.Validating.UserRole.Success'
                Write-PSFMessage -Level Verbose -String 'Invoke-AzOpsPull.Validating.AADP2'
                $servicePlanName = "AAD_PREMIUM_P2"
                $subscribedSkus = Invoke-AzRestMethod -Uri https://graph.microsoft.com/v1.0/subscribedSkus -ErrorAction Stop
                $subscribedSkusValue = $subscribedSkus.Content | ConvertFrom-Json -Depth 100 | Select-Object value
                if ($servicePlanName -in $subscribedSkusValue.value.servicePlans.servicePlanName) {
                    Write-PSFMessage -Level Verbose -String 'Invoke-AzOpsPull.Validating.AADP2.Success'
                }
                else {
                    Write-PSFMessage -Level Warning -String 'Invoke-AzOpsPull.Validating.AADP2.Failed'
                    $SkipPim = $true
                }
            }
            catch {
                Write-PSFMessage -Level Warning -String 'Invoke-AzOpsPull.Validating.UserRole.Failed'
                $SkipPim = $true
            }
        }

        if ($false -eq $SkipChildResource -or $false -eq $SkipResource -and $true -eq $SkipResourceGroup) {
            Write-PSFMessage -Level Warning -String 'Invoke-AzOpsPull.Validating.ResourceGroupDiscovery.Failed' -StringValues "`n"
        }

        $resourceTypeDiff = Compare-Object -ReferenceObject $SkipResourceType -DifferenceObject $IncludeResourceType -ExcludeDifferent
        if ($resourceTypeDiff) {
            Write-PSFMessage -Level Warning -Message "SkipResourceType setting conflict found in IncludeResourceType, ignoring $($resourceTypeDiff.InputObject) from IncludeResourceType. To avoid this remove $($resourceTypeDiff.InputObject) from IncludeResourceType or SkipResourceType"
            $IncludeResourceType = $IncludeResourceType | Where-Object { $_ -notin $resourceTypeDiff.InputObject }
        }

        Assert-AzOpsInitialization -Cmdlet $PSCmdlet -StatePath $StatePath

        $tenantId = (Get-AzContext).Tenant.Id
        Write-PSFMessage -Level Important -String 'Invoke-AzOpsPull.Tenant' -StringValues $tenantId
        Write-PSFMessage -Level Verbose -String 'Invoke-AzOpsPull.TemplateParameterFileSuffix' -StringValues (Get-PSFConfigValue -FullName 'AzOps.Core.TemplateParameterFileSuffix')

        Write-PSFMessage -Level Important -String 'Invoke-AzOpsPull.Initialization.Completed'
        $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        #endregion Initialize & Prepare
    }

    process {
        #region Existing Content
        if (Test-Path $StatePath) {
            $migrationRequired = (Get-ChildItem -Recurse -Force -Path $StatePath -File | Where-Object {
                    $_.Name -like $("Microsoft.Management_managementGroups-" + $tenantId + $TemplateParameterFileSuffix)
                } | Select-Object -ExpandProperty FullName -First 1) -notmatch '\((.*)\)'
            if ($migrationRequired) {
                Write-PSFMessage -Level Important -String 'Invoke-AzOpsPull.Migration.Required'
            }

            if ($Force -or $migrationRequired) {
                Invoke-PSFProtectedCommand -ActionString 'Invoke-AzOpsPull.Deleting.State' -ActionStringValues $StatePath -Target $StatePath -ScriptBlock {
                    Remove-Item -Path $StatePath -Recurse -Force -Confirm:$false -ErrorAction Stop
                } -EnableException $true -PSCmdlet $PSCmdlet
            }
            if ($Rebuild) {
                Invoke-PSFProtectedCommand -ActionString 'Invoke-AzOpsPull.Rebuilding.State' -ActionStringValues $StatePath -Target $StatePath -ScriptBlock {
                    Get-ChildItem -Path $StatePath  -File -Recurse -Force -Filter 'Microsoft.*_*.json' | Remove-Item -Force -Recurse -Confirm:$false -ErrorAction Stop
                } -EnableException $true -PSCmdlet $PSCmdlet
            }
        }
        #endregion Existing Content

        #region Root Scopes
        $rootScope = '/providers/Microsoft.Management/managementGroups/{0}' -f $tenantId
        if ($script:AzOpsPartialRoot.id) {
            $rootScope = $script:AzOpsPartialRoot.id | Sort-Object -Unique
        }

        # Parameters
        $parameters = $PSBoundParameters | ConvertTo-PSFHashtable -Inherit -Include IncludeResourcesInResourceGroup, IncludeResourceType, SkipPim, SkipLock, SkipPolicy, SkipRole, SkipResourceGroup, SkipChildResource, SkipResource, SkipResourceType, StatePath

        Write-PSFMessage -Level Important -String 'Invoke-AzOpsPull.Building.State' -StringValues $StatePath
        if ($rootScope -and $script:AzOpsAzManagementGroup) {
            foreach ($root in $rootScope) {
                # Create AzOpsState structure recursively
                Save-AzOpsManagementGroupChild -Scope $root -StatePath $StatePath
                Get-AzOpsResourceDefinition -Scope $root @parameters
            }
        }
        else {
            # If no management groups are found, iterate through each subscription
            foreach ($subscription in $script:AzOpsSubscriptions) {
                ConvertTo-AzOpsState -Resource (Get-AzSubscription -SubscriptionId $subscription.subscriptionId) -StatePath $StatePath
                Get-AzOpsResourceDefinition -Scope $subscription.id @parameters
            }
        }
        #endregion Root Scopes
    }

    end {
        $stopWatch.Stop()
        Write-PSFMessage -Level Important -String 'Invoke-AzOpsPull.Duration' -StringValues $stopWatch.Elapsed -Data @{ Elapsed = $stopWatch.Elapsed }
    }

}