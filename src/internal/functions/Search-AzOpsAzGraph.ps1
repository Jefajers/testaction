function Search-AzOpsAzGraph {
    <#
        .SYNOPSIS
            Search Graph based on input query combined with scope ManagementGroupName or SubscriptionId.
            Manages paging of results, ensuring completeness of results.
        .PARAMETER ManagementGroupName
            ManagementGroup Name
        .PARAMETER SubscriptionId
            Subscription Id
        .PARAMETER Query
            AzureResourceGraph-Query
        .EXAMPLE
            > Search-AzOpsAzGraph -ManagementGroupName "5663f39e-feb1-4303-a1f9-cf20b702de61" -Query "policyresources | where type == 'microsoft.authorization/policyassignments'"
            Discover all policy assignments deployed at Management Group scope and below
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]
        $ManagementGroupName,
        [Parameter(Mandatory = $false)]
        [string]
        $SubscriptionId,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Object]
        $Query
    )

    process {
        Write-PSFMessage -Level Verbose -String 'Search-AzOpsAzGraph.Processing' -StringValues $Query
        $results = @()
        do {
            if ($ManagementGroupName) {
                $processing = Search-AzGraph -ManagementGroup $ManagementGroupName -Query $Query -SkipToken $processing.SkipToken -ErrorAction Stop
            }
            elseif ($SubscriptionId) {
                $processing = Search-AzGraph -Subscription $SubscriptionId -Query $Query -SkipToken $processing.SkipToken -ErrorAction Stop
            }
            $results += $processing
        }
        while ($processing.SkipToken)

        if ($results) {
            Write-PSFMessage -Level Verbose -String 'Search-AzOpsAzGraph.Processing.Done' -StringValues $Query
            return $results
        }
        else {
            Write-PSFMessage -Level Verbose -String 'Search-AzOpsAzGraph.Processing.NoResult' -StringValues $Query
        }
    }
}