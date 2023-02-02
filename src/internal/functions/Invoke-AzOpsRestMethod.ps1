function Invoke-AzOpsRestMethod {
    <#
        .SYNOPSIS
            Process Path with given Method and manage paging of results and returns value's
        .PARAMETER Path
            Path
        .PARAMETER Method
            Method
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Object]
        $Path,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Method
    )

    process {
        # Process Path with given Method
        Write-PSFMessage -Level Debug -String 'Invoke-AzOpsRestMethod.Processing' -StringValues $Path
        $allresults = do {
            $results = ((Invoke-AzRestMethod -Path $Path -Method $Method).Content | ConvertFrom-Json -Depth 100)
            $results.value
            $path = $results.nextLink -replace 'https://management\.azure\.com'
        }
        while ($path)
        if ($allresults) {
            return $allresults
        }
    }
}