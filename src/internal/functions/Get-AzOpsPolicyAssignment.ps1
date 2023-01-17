function Get-AzOpsPolicyAssignment {

    <#
        .SYNOPSIS
            Discover all custom policy assignments at the provided scope (Management Groups, subscriptions or resource groups)
        .DESCRIPTION
            Discover all custom policy assignments at the provided scope (Management Groups, subscriptions or resource groups)
        .PARAMETER ScopeObject
            The scope object representing the azure entity to retrieve policyset definitions for.
        .EXAMPLE
            > Get-AzOpsPolicyAssignment -ScopeObject (New-AzOpsScope -Scope /providers/Microsoft.Management/managementGroups/contoso -StatePath $StatePath)
            Discover all custom policy assignments deployed at Management Group scope
    #>

    [OutputType([Microsoft.Azure.Commands.ResourceManager.Cmdlets.Implementation.Policy.PsPolicyAssignment])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Object]
        $ScopeObject,
        [Parameter(Mandatory = $true)]
        $SubscriptionIds,
        [Parameter(Mandatory = $false)]
        $SubscriptionsToIncludeResourceGroups,
        [Parameter(Mandatory = $false)]
        $ResourceGroups
    )

    process {
        if ($ScopeObject.Type -notin 'resourcegroups', 'subscriptions', 'managementGroups') {
            return
        }

        switch ($ScopeObject.Type) {
            managementGroups {
                Write-PSFMessage -Level Important -String 'Get-AzOpsPolicyAssignment.ManagementGroup' -StringValues $ScopeObject.ManagementGroupDisplayName, $ScopeObject.ManagementGroup -Target $ScopeObject
                if ($SubscriptionsToIncludeResourceGroups -and $ResourceGroups) {
                    $query = "policyresources | where type == 'microsoft.authorization/policyassignments' and subscriptionId in ($SubscriptionsToIncludeResourceGroups) and resourceGroup in ($ResourceGroups) | order by ['id'] asc"
                }
                elseif ($SubscriptionIds -and $ResourceGroups) {
                    $query = "policyresources | where type == 'microsoft.authorization/policyassignments' and subscriptionId in ($SubscriptionIds) and resourceGroup in ($ResourceGroups) | order by ['id'] asc"
                }
                else {
                    $query = "policyresources | where type == 'microsoft.authorization/policyassignments' and resourceGroup == '' | where subscriptionId == '' or subscriptionId in ($SubscriptionIds) | order by ['id'] asc"
                }
                Search-AzOpsAzGraph -ManagementGroup $ScopeObject.Name -Query $query -ErrorAction Stop
            }
            subscriptions {
                Write-PSFMessage -Level Important -String 'Get-AzOpsPolicyAssignment.Subscription' -StringValues $ScopeObject.SubscriptionDisplayName, $ScopeObject.Subscription -Target $ScopeObject
                $query = "policyresources | where type == 'microsoft.authorization/policyassignments' and resourceGroup == '' and subscriptionId == '$($ScopeObject.Name)' | where id startswith '$($ScopeObject.Scope)' | order by ['id'] asc"
                Search-AzOpsAzGraph -SubscriptionId $ScopeObject.Name -Query $query -ErrorAction Stop
            }
            resourcegroups {
                Write-PSFMessage -Level Important -String 'Get-AzOpsPolicyAssignment.ResourceGroup' -StringValues $ScopeObject.ResourceGroup -Target $ScopeObject
                $query = "policyresources | where type == 'microsoft.authorization/policyassignments' and resourceGroup == '$($ScopeObject.Name.Tolower())' and subscriptionId == '$($ScopeObject.Subscription)' | where id startswith '$($ScopeObject.Scope)' | order by ['id'] asc"
                Search-AzOpsAzGraph -SubscriptionId $ScopeObject.Subscription -Query $query -ErrorAction Stop
            }
        }
    }

}