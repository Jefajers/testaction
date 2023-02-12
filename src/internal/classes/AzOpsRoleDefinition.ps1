class AzOpsRoleDefinition {
    [string]$type
    [string]$name
    [string]$id
    [hashtable]$properties
    AzOpsRoleDefinition($properties) {
        # Removing the Trailing slash to ensure that '/' is not appended twice when adding '/providers/xxx'.
        # Example: '/subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/' is a valid assignment scope.
        $this.id = '/' + $properties.properties.assignableScopes[0].Trim('/') + '/providers/Microsoft.Authorization/roleDefinitions/' + $properties.id
        $this.name = $properties.name
        $this.properties = [ordered]@{
            assignableScopes = @($properties.properties.assignableScopes)
            description	     = $properties.properties.description
            permissions	     = @(
                [ordered]@{
                    actions = @($properties.properties.permissions.actions)
                    dataActions = @($properties.properties.permissions.dataActions)
                    notActions = @($properties.properties.permissions.notActions)
                    notDataActions = @($properties.properties.permissions.notDataActions)
                }
            )
        }
        $this.type = $properties.type
    }
}