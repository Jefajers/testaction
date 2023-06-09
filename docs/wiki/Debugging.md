## Debugging AzOps Locally - Walkthrough

If you're having issues with AzOps in your CI/CD system, it can be helpful to troubleshoot locally. For this example, we're going to use VS Code as the IDE (in a Windows 10 environment).

### Prerequisites

1. [Visual Studio Code](https://code.visualstudio.com/)
1. The [PowerShell Visual Studio Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell)
1. JQ (Installing JQ from [Choco](https://community.chocolatey.org/packages/jq) using `choco install jq --verbose -y` and then add its directory (C:\ProgramData\chocolatey\lib\jq\tools) to the PATH env variable)

### Getting started

1. Clone the [project](https://github.com/Azure/AzOps) from GitHub and open with Visual Studio Code
1. Run `Dependencies.ps1` from the scripts directory to install the dependant PoSH modules`
1. Login with the correct service principal that has Management Group scope access

```powershell
Clear-AzContext
$Credential = Get-Credential
Connect-AzAccount -Credential $Credential -Tenant xxxx-xxx-xxxx-xxxx-xxx -ServicePrincipal
```

4. Open `Debug.ps1` and observe the value for `PSFramework.Message.Info.Maximum` which indicates the level of verbosity used for logging.  This can be changed further into the debugging process.
1. Run `Debug.ps1`
1. Let the process finish, and observe the new file structure in the repository root.  If this completes without error, then the `Pull` operation should operate without issue in your CI/CD system.

### Making a change

Running `Debug.ps1` in the last step leaves us on a [nested prompt](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.host.pshost.enternestedprompt). We're now able to feed in new Powershell commands at the command prompt to run in the correct context.

In this example, we're going to provide a new ARM template at a specific scope. The Arm template is the [Create New Subscription](https://github.com/Azure/Enterprise-Scale/blob/main/examples/landing-zones/empty-subscription/emptySubscription.json)
 template from the Enterprise Scale repo, it has had default values provided for each of the parameters. The file is being dropped it inside the file structure that was created in the last step, inside the `Sandboxes` directory; `root\myorg (myorg)\myorg-sandboxes (myorg-sandboxes`).

At the command prompt we'll provide it the json file path (wrapped as a changeset object), and then run the cmdlet to Invoke the AzOps Change process.

```powershell
$ChangeSet = @("M`troot\myorg (myorg)\myorg-sandboxes (myorg-sandboxes)\new-subscription.json")
Invoke-AzOpsPush -ChangeSet $ChangeSet
```

You can then monitor the PowerShell terminal in VS Code to see the Deployment complete with the accompanying logs.

## Additional Notes

### PowerShell Settings

Modify the default output state path generated by the module.

```powershell
Set-PSFConfig -FullName AzOps.Core.State -Value "/tmp/azops"
```

Increase the verbosity of the logging messages.

```powershell
Set-PSFConfig PSFramework.Message.Info.Maximum 9
```

Increase the max retention count of log messages.

```powershell
Set-PSFConfig PSFramework.Logging.MaxMessageCount 1MB
```

### VS Code Settings

By default, setting breakpoints on AzOps in VS Code will not work.
This is due to the files being invoked as scriptblock by default, rather than as file, for performance reasons.
To work around this issue, set a configuration setting to disable this behavior:

```powershell
Set-PSFConfig AzOps.Import.DoDotSource $true
```

You can make it remember that by registering the setting:

```powershell
Set-PSFConfig AzOps.Import.DoDotSource $true -PassThru | Register-PSFConfig
```
