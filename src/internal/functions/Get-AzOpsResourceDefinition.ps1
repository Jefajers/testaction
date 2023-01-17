function Get-AzOpsResourceDefinition {

    <#
        .SYNOPSIS
            This cmdlet recursively discovers resources (Management Groups, Subscriptions, Resource Groups, Resources, Privileged Identity Management resources, Policies, Role Assignments) from the provided input scope.
        .DESCRIPTION
            This cmdlet recursively discovers resources (Management Groups, Subscriptions, Resource Groups, Resources, Privileged Identity Management resources, Policies, Role Assignments) from the provided input scope.
        .PARAMETER Scope
            Discovery Scope
        .PARAMETER IncludeResourcesInResourceGroup
            Discover only resources in these resource groups.
        .PARAMETER IncludeResourceType
            Discover only specific resource types.
        .PARAMETER SkipChildResource
            Skip childResource discovery.
        .PARAMETER SkipPim
            Skip discovery of Privileged Identity Management.
        .PARAMETER SkipLock
            Skip discovery of resourceLock.
        .PARAMETER SkipPolicy
            Skip discovery of policies.
        .PARAMETER SkipResource
            Skip discovery of resources inside resource groups.
        .PARAMETER SkipResourceGroup
            Skip discovery of resource groups.
        .PARAMETER SkipResourceType
            Skip discovery of specific resource types.
        .PARAMETER SkipUnsupportedChildResourceType
            Skip discovery of unsupported child resource types.
        .PARAMETER SkipRole
            Skip discovery of roles for better performance.
        .PARAMETER ExportRawTemplate
            Export generic templates without embedding them in the parameter block.
        .PARAMETER StatePath
            The root folder under which to write the resource json.
        .EXAMPLE
            $TenantRootId = '/providers/Microsoft.Management/managementGroups/{0}' -f (Get-AzTenant).Id
            Get-AzOpsResourceDefinition -scope $TenantRootId -Verbose
            Discover all resources from root Management Group
        .EXAMPLE
            Get-AzOpsResourceDefinition -scope /providers/Microsoft.Management/managementGroups/landingzones -SkipPolicy -SkipResourceGroup
            Discover all resources from child Management Group, skip discovery of policies and resource groups
        .EXAMPLE
            Get-AzOpsResourceDefinition -scope /subscriptions/623625ae-cfb0-4d55-b8ab-0bab99cbf45c
            Discover all resources from Subscription level
        .EXAMPLE
            Get-AzOpsResourceDefinition -scope /subscriptions/623625ae-cfb0-4d55-b8ab-0bab99cbf45c/resourceGroups/myresourcegroup
            Discover all resources from resource group level
        .EXAMPLE
            Get-AzOpsResourceDefinition -scope /subscriptions/623625ae-cfb0-4d55-b8ab-0bab99cbf45c/resourceGroups/contoso-global-dns/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net
            Discover a single resource
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Scope,

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

        [string[]]
        $SkipUnsupportedChildResourceType = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipUnsupportedChildResourceType'),

        [switch]
        $SkipRole = (Get-PSFConfigValue -FullName 'AzOps.Core.SkipRole'),

        [switch]
        $ExportRawTemplate = (Get-PSFConfigValue -FullName 'AzOps.Core.ExportRawTemplate'),

        [Parameter(Mandatory = $false)]
        [string]
        $StatePath = (Get-PSFConfigValue -FullName 'AzOps.Core.State')
    )

    begin {
        # Set variables for retry with exponential backoff
        $backoffMultiplier = 2
        $maxRetryCount = 6
        # Logging output metadata
        $common = @{
            FunctionName = 'Get-AzOpsResourceDefinition'
            Target       = $ScopeObject
        }
        # Prepare Input Data for parallel processing
        $runspaceData = @{
            AzOpsPath                       = "$($script:ModuleRoot)\AzOps.psd1"
            StatePath                       = $StatePath
            runspace_AzOpsAzManagementGroup = $script:AzOpsAzManagementGroup
            runspace_AzOpsSubscriptions     = $script:AzOpsSubscriptions
            runspace_AzOpsPartialRoot       = $script:AzOpsPartialRoot
            runspace_AzOpsResourceProvider  = $script:AzOpsResourceProvider
            BackoffMultiplier               = $backoffMultiplier
            MaxRetryCount                   = $maxRetryCount
        }
    }

    process {
        Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Processing' -StringValues $Scope
        try {
            $scopeObject = New-AzOpsScope -Scope $Scope -StatePath $StatePath -ErrorAction Stop
        }
        catch {
            Write-PSFMessage -Level Warning -String 'Get-AzOpsResourceDefinition.Processing.NotFound' -StringValues $Scope
            return
        }
        if ($scopeObject.Type -notin 'subscriptions', 'managementGroups') {
            Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Finished' -StringValues $scopeObject.Scope
            return
        }
        # Construct object with subscription attributes to exclude in graph query
        (Get-PSFConfigValue -FullName 'AzOps.Core.ExcludedSubOffer') | ForEach-Object { $ExcludedOffers += ($(if($ExcludedOffers){","}) + "'" + $_  + "'") }
        (Get-PSFConfigValue -FullName 'AzOps.Core.ExcludedSubState') | ForEach-Object { $ExcludedStates += ($(if($ExcludedStates){","}) + "'" + $_  + "'") }
        switch ($scopeObject.Type) {
            subscriptions {
                Write-PSFMessage -Level Important @common -String 'Get-AzOpsResourceDefinition.Subscription.Processing' -StringValues $ScopeObject.SubscriptionDisplayName, $ScopeObject.Subscription
                $query = "resourcecontainers | where type == 'microsoft.resources/subscriptions' and properties.subscriptionPolicies.quotaId !in ($ExcludedOffers) and properties.state !in ($ExcludedStates) | order by ['id'] asc"
                $subscriptions = Search-AzOpsAzGraph -SubscriptionId $scopeObject.Name -Query $query -ErrorAction Stop | Where-Object { $_.id -in $script:AzOpsSubscriptions.id }
                $subscriptions.subscriptionId | ForEach-Object { $subscriptionIds += ($(if($subscriptionIds){","}) + "'" + $_  + "'") }
            }
            managementGroups {
                Write-PSFMessage -Level Important @common -String 'Get-AzOpsResourceDefinition.ManagementGroup.Processing' -StringValues $ScopeObject.ManagementGroupDisplayName, $ScopeObject.ManagementGroup
                $query = "resourcecontainers | where type == 'microsoft.management/managementgroups' | order by ['id'] asc"
                $managementgroups = Search-AzOpsAzGraph -ManagementGroup $scopeObject.Name -Query $query -ErrorAction Stop | Where-Object { $_.id -in $script:AzOpsAzManagementGroup.Id }
                $query = "resourcecontainers | where type == 'microsoft.resources/subscriptions' and properties.subscriptionPolicies.quotaId !in ($ExcludedOffers) and properties.state !in ($ExcludedStates) | order by ['id'] asc"
                $subscriptions = Search-AzOpsAzGraph -ManagementGroup $scopeObject.Name -Query $query -ErrorAction Stop | Where-Object { $_.id -in $script:AzOpsSubscriptions.id }
                $subscriptions.subscriptionId | ForEach-Object { $subscriptionIds += ($(if($subscriptionIds){","}) + "'" + $_  + "'") }
                if ($managementgroups) {
                    # Process managementGroup scope in parallel
                    $managementgroups | Foreach-Object -ThrottleLimit (Get-PSFConfigValue -FullName 'AzOps.Core.ThrottleLimit') -Parallel {
                        $managementgroup = $_
                        $runspaceData = $using:runspaceData

                        $msgCommon = @{
                            FunctionName = $using:common.FunctionName
                            ModuleName   = 'AzOps'
                        }

                        Import-Module "$([PSFramework.PSFCore.PSFCoreHost]::ModuleRoot)/PSFramework.psd1"
                        $azOps = Import-Module $runspaceData.AzOpsPath -Force -PassThru
                        & $azOps {
                            $script:AzOpsAzManagementGroup = $runspaceData.runspace_AzOpsAzManagementGroup
                            $script:AzOpsSubscriptions = $runspaceData.runspace_AzOpsSubscriptions
                            $script:AzOpsPartialRoot = $runspaceData.runspace_AzOpsPartialRoot
                            $script:AzOpsResourceProvider = $runspaceData.runspace_AzOpsResourceProvider
                        }
                        #region Process Privileged Identity Management resources, Policies and Roles at managementGroup scope
                        if ((-not $using:SkipPim) -or (-not $using:SkipPolicy) -or (-not $using:SkipRole)) {
                            & $azOps {
                                $ScopeObject = New-AzOpsScope -Scope $managementgroup.id -StatePath $runspaceData.Statepath -ErrorAction Stop
                                if (-not $using:SkipPim) {
                                    Get-AzOpsPim -ScopeObject $ScopeObject -StatePath $runspaceData.Statepath
                                }
                                if (-not $using:SkipPolicy) {
                                    Write-PSFMessage -Level Verbose @msgCommon -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Exemptions', $ScopeObject.Scope
                                    $policyExemptions = Get-AzOpsPolicyExemption -ScopeObject $ScopeObject
                                    $policyExemptions | ConvertTo-AzOpsState -StatePath $runspaceData.Statepath
                                }
                                if (-not $using:SkipRole) {
                                    Get-AzOpsRole -ScopeObject $ScopeObject -StatePath $runspaceData.Statepath
                                }
                            }
                        }
                    }
                }
            }
        }
        #region Process Resource Groups
        if ($SkipResourceGroup) {
            Write-PSFMessage -Level Verbose @common -String 'Get-AzOpsResourceDefinition.Subscription.SkippingResourceGroup'
        }
        else {
            if ((Get-PSFConfigValue -FullName 'AzOps.Core.SubscriptionsToIncludeResourceGroups') -ne '*') {
                (Get-PSFConfigValue -FullName 'AzOps.Core.SubscriptionsToIncludeResourceGroups') | ForEach-Object { $subscriptionsToIncludeResourceGroups += ($(if($subscriptionsToIncludeResourceGroups){","}) + "'" + $_  + "'") }
                $query = "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' and subscriptionId in ($subscriptionIds) and subscriptionId in ($subscriptionsToIncludeResourceGroups) | where managedBy == '' | order by ['id'] asc"
            } else {
                $query = "resourcecontainers | where type == 'microsoft.resources/subscriptions/resourcegroups' and subscriptionId in ($subscriptionIds) | where managedBy == '' | order by ['id'] asc"
            }
            switch ($scopeObject.Type) {
                subscriptions {
                    $resourceGroups = Search-AzOpsAzGraph -SubscriptionId $scopeObject.Name -Query $query -ErrorAction Stop
                }
                managementGroups {
                    $resourceGroups = Search-AzOpsAzGraph -ManagementGroup $scopeObject.Name -Query $query -ErrorAction Stop
                }
            }
            $resourceGroups.resourceGroup | ForEach-Object { $resourceGroupsString += ($(if($resourceGroupsString){","}) + "'" + $_  + "'") }
            if ($resourceGroups) {
                # Loop resource groups
                foreach ($resourceGroup in $resourceGroups) {
                    # Convert resourceGroup to AzOpsState
                    Write-PSFMessage -Level Verbose @common -String 'Get-AzOpsResourceDefinition.Subscription.Processing.ResourceGroup' -StringValues $resourceGroup.name -Target $resourceGroup
                    ConvertTo-AzOpsState -Resource $resourceGroup -ExportRawTemplate:$ExportRawTemplate -StatePath $Statepath
                }
                # Process resource groups parallel
                $resourceGroups | Foreach-Object -ThrottleLimit (Get-PSFConfigValue -FullName 'AzOps.Core.ThrottleLimit') -Parallel {
                    $resourceGroup = $_
                    $runspaceData = $using:runspaceData

                    $msgCommon = @{
                        FunctionName = $using:common.FunctionName
                        ModuleName   = 'AzOps'
                    }

                    Import-Module "$([PSFramework.PSFCore.PSFCoreHost]::ModuleRoot)/PSFramework.psd1"
                    $azOps = Import-Module $runspaceData.AzOpsPath -Force -PassThru
                    & $azOps {
                        $script:AzOpsAzManagementGroup = $runspaceData.runspace_AzOpsAzManagementGroup
                        $script:AzOpsSubscriptions = $runspaceData.runspace_AzOpsSubscriptions
                        $script:AzOpsPartialRoot = $runspaceData.runspace_AzOpsPartialRoot
                        $script:AzOpsResourceProvider = $runspaceData.runspace_AzOpsResourceProvider
                    }
                    #region Process Privileged Identity Management resources, Policies, Locks and Roles at RG scope
                    if ((-not $using:SkipPim) -or (-not $using:SkipPolicy) -or (-not $using:SkipRole) -or (-not $using:SkipLock)) {
                        & $azOps {
                            $rgScopeObject = New-AzOpsScope -Scope $resourceGroup.id -StatePath $runspaceData.Statepath -ErrorAction Stop
                            if (-not $using:SkipLock) {
                                Get-AzOpsResourceLock -ScopeObject $rgScopeObject -StatePath $runspaceData.Statepath
                            }
                            if (-not $using:SkipPim) {
                                Get-AzOpsPim -ScopeObject $rgScopeObject -StatePath $runspaceData.Statepath
                            }
                            if (-not $using:SkipPolicy) {
                                Write-PSFMessage -Level Verbose @msgCommon -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Exemptions', $rgScopeObject.Scope
                                $policyExemptions = Get-AzOpsPolicyExemption -ScopeObject $rgScopeObject
                                $policyExemptions | ConvertTo-AzOpsState -StatePath $runspaceData.Statepath
                            }
                            if (-not $using:SkipRole) {
                                Get-AzOpsRole -ScopeObject $rgScopeObject -StatePath $runspaceData.Statepath
                            }
                        }
                    }
                }
            }
            #region Process Policies
            if (-not $SkipPolicy) {
                if ($subscriptionsToIncludeResourceGroups) {
                    Get-AzOpsPolicy -ScopeObject $scopeObject -SubscriptionId $subscriptionIds -SubscriptionsToIncludeResourceGroups $subscriptionsToIncludeResourceGroups -ResourceGroups $resourceGroupsString -StatePath $StatePath
                }
                else {
                    Get-AzOpsPolicy -ScopeObject $scopeObject -SubscriptionId $subscriptionIds -ResourceGroups $resourceGroupsString -StatePath $StatePath
                }
            }
            #endregion Process Policies
            if (-not $SkipResource) {
                $SkipResourceType | ForEach-Object { $skipResourceTypes += ($(if($skipResourceTypes){","}) + "'" + $_  + "'") }
                $IncludeResourceType | ForEach-Object { $includeResourceTypes += ($(if($includeResourceTypes){","}) + "'" + $_  + "'") }
                if ($IncludeResourceType -eq "*") {
                    $query = "resources | where subscriptionId in ($subscriptionIds) and type !in ($skipResourceTypes) | order by ['id'] asc"
                }
                else {
                    $query = "resources | where subscriptionId in ($subscriptionIds) and type !in ($skipResourceTypes) and type in ($includeResourceTypes) | order by ['id'] asc"
                }
                switch ($scopeObject.Type) {
                    subscriptions {
                        $resourcesBase = Search-AzOpsAzGraph -SubscriptionId $scopeObject.Name -Query $query -ErrorAction Stop
                    }
                    managementGroups {
                        $resourcesBase = Search-AzOpsAzGraph -ManagementGroup $scopeObject.Name -Query $query -ErrorAction Stop
                    }
                }
                $resources = @()
                foreach ($resource in $resourcesBase) {
                    if ($resourceGroups | Where-Object { $_.name -eq $resource.resourceGroup -and $_.subscriptionId -eq $resource.subscriptionId } ) {
                        # Convert resources to AzOpsState
                        Write-PSFMessage -Level Verbose @common -String 'Get-AzOpsResourceDefinition.Subscription.Processing.Resource' -StringValues $resource.name, $resource.resourcegroup -Target $resource
                        $resources += $resource
                        ConvertTo-AzOpsState -Resource $resource -ExportRawTemplate:$ExportRawTemplate -StatePath $Statepath
                    }
                }
            }
            if (-not $SkipResource -and -not $SkipChildResource) {
                # Process resource scope in parallel looking for childResource
                $resources | Foreach-Object -ThrottleLimit (Get-PSFConfigValue -FullName 'AzOps.Core.ThrottleLimit') -Parallel {
                    $resource = $_
                    $runspaceData = $using:runspaceData

                    $msgCommon = @{
                        FunctionName = $using:common.FunctionName
                        ModuleName   = 'AzOps'
                    }

                    Import-Module "$([PSFramework.PSFCore.PSFCoreHost]::ModuleRoot)/PSFramework.psd1"
                    $azOps = Import-Module $runspaceData.AzOpsPath -Force -PassThru
                    & $azOps {
                        $script:AzOpsAzManagementGroup = $runspaceData.runspace_AzOpsAzManagementGroup
                        $script:AzOpsSubscriptions = $runspaceData.runspace_AzOpsSubscriptions
                        $script:AzOpsPartialRoot = $runspaceData.runspace_AzOpsPartialRoot
                        $script:AzOpsResourceProvider = $runspaceData.runspace_AzOpsResourceProvider
                    }
                    $context = Get-AzContext
                    $context.Subscription.Id = $resource.subscriptionId
                    $tempExportPath = [System.IO.Path]::GetTempPath() + (New-Guid).ToString() + '.json'
                    try {
                        & $azOps {
                            $exportParameters = @{
                                Resource                = $resource.id
                                ResourceGroupName       = $resource.resourceGroup
                                SkipAllParameterization = $true
                                Path                    = $tempExportPath
                                DefaultProfile          = $context | Select-Object -First 1
                            }
                            Invoke-AzOpsScriptBlock -ArgumentList $exportParameters -ScriptBlock {
                                param (
                                    $ExportParameters
                                )
                                $param = $ExportParameters | Write-Output
                                Export-AzResourceGroup @param -Confirm:$false -Force -ErrorAction Stop | Out-Null
                            } -RetryCount $runspaceData.MaxRetryCount -RetryWait $runspaceData.BackoffMultiplier -RetryType Exponential
                        }
                        $exportResources = (Get-Content -Path $tempExportPath | ConvertFrom-Json).resources
                        $resourceGroup = $using:resourceGroups | Where-Object {$_.subscriptionId -eq $resource.subscriptionId -and $_.name -eq $resource.resourceGroup}
                        foreach ($exportResource in $exportResources) {
                            if (-not(($resource.name -eq $exportResource.name) -and ($resource.type -eq $exportResource.type))) {
                                Write-PSFMessage -Level Verbose @msgCommon -String 'Get-AzOpsResourceDefinition.Subscription.Processing.ChildResource' -StringValues $exportResource.name, $resource.resourceGroup -Target $exportResource
                                $ChildResource = @{
                                    resourceProvider = $exportResource.type -replace '/', '_'
                                    resourceName     = $exportResource.name -replace '/', '_'
                                    parentResourceId = $resourceGroup.id
                                }
                                if (Get-Member -InputObject $exportResource -name 'dependsOn') {
                                    $exportResource.PsObject.Members.Remove('dependsOn')
                                }
                                $resourceHash = @{resources = @($exportResource) }
                                & $azOps {
                                    ConvertTo-AzOpsState -Resource $resourceHash -ChildResource $ChildResource -StatePath $runspaceData.Statepath
                                }
                            }
                        }
                    }
                    catch {
                        Write-PSFMessage -Level Warning @msgCommon -String 'Get-AzOpsResourceDefinition.ChildResource.Warning' -StringValues $resource.resourceGroup, $_
                    }
                    if (Test-Path -Path $tempExportPath) {
                        Remove-Item -Path $tempExportPath
                    }
                }
            }
            else {
                Write-PSFMessage -Level Verbose @common -String 'Get-AzOpsResourceDefinition.Subscription.SkippingChildResource'
            }
        }
        #endregion Process Resource Groups

        #region Process Policies
        if (-not $SkipPolicy) {
            Get-AzOpsPolicy -ScopeObject $scopeObject -SubscriptionIds $subscriptionIds -StatePath $StatePath
        }
        #endregion Process Policies
        if ($subscriptions) {
            # Process subscription scope in parallel
            $subscriptions | Foreach-Object -ThrottleLimit (Get-PSFConfigValue -FullName 'AzOps.Core.ThrottleLimit') -Parallel {
                $subscription = $_
                $runspaceData = $using:runspaceData

                $msgCommon = @{
                    FunctionName = $using:common.FunctionName
                    ModuleName   = 'AzOps'
                }

                Import-Module "$([PSFramework.PSFCore.PSFCoreHost]::ModuleRoot)/PSFramework.psd1"
                $azOps = Import-Module $runspaceData.AzOpsPath -Force -PassThru
                # endregion Importing module
                & $azOps {
                    $script:AzOpsAzManagementGroup = $runspaceData.runspace_AzOpsAzManagementGroup
                    $script:AzOpsSubscriptions = $runspaceData.runspace_AzOpsSubscriptions
                    $script:AzOpsPartialRoot = $runspaceData.runspace_AzOpsPartialRoot
                    $script:AzOpsResourceProvider = $runspaceData.runspace_AzOpsResourceProvider
                }
                #region Process Privileged Identity Management resources, Policies, Locks and Roles at subscription scope
                if ((-not $using:SkipPim) -or (-not $using:SkipPolicy) -or (-not $using:SkipLock) -or (-not $using:SkipRole)) {
                    & $azOps {
                        $scopeObject = New-AzOpsScope -Scope $subscription.id -StatePath $runspaceData.Statepath -ErrorAction Stop
                        if (-not $using:SkipPim) {
                            Get-AzOpsPim -ScopeObject $scopeObject -StatePath $runspaceData.Statepath
                        }
                        if (-not $using:SkipPolicy) {
                            Write-PSFMessage -Level Verbose @msgCommon -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Exemptions', $scopeObject.Scope
                            $policyExemptions = Get-AzOpsPolicyExemption -ScopeObject $scopeObject
                            $policyExemptions | ConvertTo-AzOpsState -StatePath $runspaceData.Statepath
                        }
                        if (-not $using:SkipLock) {
                            Get-AzOpsResourceLock -ScopeObject $scopeObject -StatePath $runspaceData.Statepath
                        }
                        if (-not $using:SkipRole) {
                            Get-AzOpsRole -ScopeObject $scopeObject -StatePath $runspaceData.Statepath
                        }
                    }
                }
            }
        }
        Write-PSFMessage -Level Verbose @common -String 'Get-AzOpsResourceDefinition.Finished' -StringValues $scopeObject.Scope
    }
}