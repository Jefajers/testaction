function Get-AzOpsPolicy {
    <#
        .SYNOPSIS
            Get policy objects from provided scope
        .PARAMETER ScopeObject
            ScopeObject
        .PARAMETER StatePath
            StatePath
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Object]
        $ScopeObject,
        [Parameter(Mandatory = $true)]
        $StatePath,
        [Parameter(Mandatory = $false)]
        $SubscriptionIds,
        [Parameter(Mandatory = $false)]
        $SubscriptionsToIncludeResourceGroups,
        [Parameter(Mandatory = $false)]
        $ResourceGroups
    )

    process {
        if ($ResourceGroups) {
            # Process policy assignments
            Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Assignments', $ScopeObject.Scope
            $policyAssignments = Get-AzOpsPolicyAssignment -ScopeObject $ScopeObject -SubscriptionIds $SubscriptionIds -SubscriptionsToIncludeResourceGroups $SubscriptionsToIncludeResourceGroups -ResourceGroups $ResourceGroups
            $policyAssignments | ConvertTo-AzOpsState -StatePath $StatePath
        }
        else {
            # Process policy definitions
            Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Definitions', $scopeObject.Scope
            $policyDefinitions = Get-AzOpsPolicyDefinition -ScopeObject $ScopeObject -SubscriptionIds $SubscriptionIds
            $policyDefinitions | ConvertTo-AzOpsState -StatePath $StatePath

            # Process policy set definitions (initiatives)
            Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Set Definitions', $ScopeObject.Scope
            $policySetDefinitions = Get-AzOpsPolicySetDefinition -ScopeObject $ScopeObject -SubscriptionIds $SubscriptionIds
            $policySetDefinitions | ConvertTo-AzOpsState -StatePath $StatePath

            # Process policy assignments
            Write-PSFMessage -Level Verbose -String 'Get-AzOpsResourceDefinition.Processing.Detail' -StringValues 'Policy Assignments', $ScopeObject.Scope
            $policyAssignments = Get-AzOpsPolicyAssignment -ScopeObject $ScopeObject -SubscriptionIds $SubscriptionIds -SubscriptionsToIncludeResourceGroups $SubscriptionsToIncludeResourceGroups
            $policyAssignments | ConvertTo-AzOpsState -StatePath $StatePath
        }
    }
}