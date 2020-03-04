<#
.DESCRIPTION
    Installs and configures the WSUS role
.EXAMPLE
    .\Configure-WSUSServer.ps1 -WSUSConfigJson ".\WSUS-Config.json"
.PARAMETER WSUSConfigJson
    Pass location of configuration file
#>

Param (
    [Parameter(Mandatory = $True, HelpMessage = "Specify complete path of the WSUS-Config.json")]
    [string]
    $WSUSConfigJson
)

$ErrorActionPreference = 'Stop'

$Json = Get-Content $WSUSConfigJson | Out-String | ConvertFrom-Json

Write-Output $Json

function HasScriptRun {
    try {
        $scriptrun = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows" -Name WSUSConfigScriptRun -erroraction stop
        $hasscriptrun = $scriptrun -ne 0
    }
    catch {
        $hasscriptrun = $false
    }

    $hasscriptrun
}

function ShouldScriptRun {
    $scriptshouldrun = $True

    if ([string]::IsNullOrWhitespace($Json.Force) -or ($Json.Force -ine $true)) {
        $scripthasrun = HasScriptRun
        $scriptshouldrun = ($scripthasrun -ne $true)
    }

    $scriptshouldrun
}

function SetScriptRun {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows" -Name WSUSConfigScriptRun -Value 1
}

function RunPostInstall {
    $contentdir = $Json.ContentDir

    if ([string]::IsNullOrWhitespace($contentdir)) {
        throw "Must specify WSUS content directory."
    }

    & $env:SystemDrive'\Program Files\Update Services\Tools\WsusUtil.exe' postinstall CONTENT\_DIR=$contentdir
}

function InstallWSUS {
    # Install WSUS Role i.e. WSUS Services and Management tools
    Write-Host 'Installing WSUS for WID (Windows Internal Database)'

    Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

    RunPostInstall
}

function ConfigWSUSAndPerformCategorySync {
    Set-WsusServerSynchronization –SyncFromMU

    $wsus = Get-WSUSServer
    $wsusConfig = $wsus.GetConfiguration()
    $languages = "all"

    if (-not [string]::IsNullOrWhitespace($Json.Languages)) {
        $languages = $Json.Languages
    }

    if ($languages -ieq "all") {
        Write-Host "Enabling all WSUS languages"

        $wsusConfig.AllUpdateLanguagesEnabled = $true
    }
    else {
        Write-Host "Setting WSUS languages to $languages"

        $wsusConfig.AllUpdateLanguagesEnabled = $false
        $wsusConfig.SetEnabledUpdateLanguages($languages)
    }

    if (-not [string]::IsNullOrWhitespace($Json.StoreUpdatesLocally)) {
        $storelocally = $Json.StoreUpdatesLocally -ieq $true

        Write-Host "Setting WSUS local update storage to $storelocally"

        $wsusConfig.HostBinariesOnMicrosoftUpdate = $storelocally

        if ($storelocally) {
            $useexpress = false

            if (-not [string]::IsNullOrWhitespace($Json.UseExpressInstallationOption)) {
                $useexpress = $Json.UseExpressInstallationOption -ieq $true
            }

            Write-Host "Setting WSUS express installation to $useexpress"

            $wsusConfig.DownloadExpressPackages = $useexpress
        }
    }

    $wsusConfig.Save()

    $subscription = $wsus.GetSubscription()

    Write-Host 'Beginning WSUS category sync'

    $subscription.StartSynchronizationForCategoryOnly()

    while ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 10
    }

    Write-Host "Initial sync is done."
}

function ConfigProductsForSync {
    if ($Json.Products.Length -eq 0) {
        Write-Host "No products specified"
    }
    else {
        Write-Host 'Setting WSUS Products'

        # De-select previous products
        Get-WsusServer | Get-WsusProduct | Set-WSUSProduct -Disable

        foreach ($Product in $Json.Products) {
            $productFound = Get-WsusProduct | Where-Object -FilterScript { $\_.product.title -like $Product.Value }

            if (-not [string]::IsNullOrWhitespace($productFound)) {
                Get-WsusServer | Get-WsusProduct | Where-Object -FilterScript { $\_.product.title -like $Product.Value } | Set-WsusProduct
            }
            else {
                throw "Product ($Product.Value) that requested to sync not found in the product categories"
            }
        }
    }
}

function ConfigClassificationsForSync {
    if ($Json.Classifications.Length -eq 0) {
        Write-Host "No classifications specified"
    }
    else {
        Write-Host 'Setting WSUS Classifications'

        # De-select current classifications
        Get-WsusServer | Get-WsusClassification | Set-WsusClassification -Disable

        foreach ($Classification in $Json.Classifications) {
            $classificationFound = Get-WsusClassification | Where-Object { $\_.Classification.Title -Like $Classification.Value }

            if (-not [string]::IsNullOrWhitespace($classificationFound)) {
                Get-WsusServer | Get-WsusClassification | Where-Object { $\_.Classification.Title -Like $Classification.Value } | Set-WsusClassification
            }
            else {
                throw "Classification ($Classification.Value) that requested to sync not found in the classification list"
            }
        }
    }
}

function EnableAutoApproval {
    $wsus = Get-WsusServer
    $approvalrule = $wsus.GetInstallApprovalRules() | Where-Object { $\_.Name -eq "Approve All Updates" }

    if ($approvalrule) {
        Write-Host "Using existing auto-approval rule"
    }
    else {
        $approvalrule = $wsus.CreateInstallApprovalRule("Approve All Updates")

        Write-Host "Creating new auto-approval rule"
    }

    $ApprovalRule.Enabled = $true
    $productcollection = New-Object -TypeName Microsoft.UpdateServices.Administration.UpdateCategoryCollection
    $computergroupcollection = New-Object -TypeName Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
    $allcomputers = $wsus.GetComputerTargetGroups() | Where-Object { $\_.Name -eq "All Computers" }

    if ($allcomputers) {
        $computergroupcollection.Add($allcomputers)
    }
    else {
        throw "Failed to find 'All Computers' target group"
    }

    $approvalrule.SetComputerTargetGroups($computergroupcollection)
    $approvalrule.Save()
}

function DisableAutoApproval {
    $wsus = Get-WsusServer
    $approvalrule = $wsus.GetInstallApprovalRules() | Where-Object { $\_.Name -eq "Approve All Updates" }

    if ($approvalrule) {
        Write-Host "Deleting existing auto-approval rule"
        $wsus.DeleteInstallApprovalRule($approvalrule.Id)
    }
    else {
        Write-Host "Approval rule already deleted"
    }
}

function SetAutoApproval {
    if ($Json.AutoApproveUpdates -ieq $true) {
        EnableAutoApproval
    }
    elseif ($Json.AutoApproveUpdates -ieq $false) {
        DisableAutoApproval
    }
    else {
        Write-Host"Auto-approval unchanged"
    }
}

function SetSynchronizationTypeAndStartFullSync {
    $wsus = Get-WSUSServer
    $subscription = $wsus.GetSubscription()
    $autosynccount = 0

    if (-not [string]::IsNullOrWhitespace($Json.AutoSynchronize)) {
        $autosynccount = 0 + $Json.AutoSynchronize
    }

    if ($autosynccount -eq 0) {
        Write-Host "Disabling automatic synchronization."
        $subscription.SynchronizeAutomatically = $false
    }
    else {
        Write-Host "Setting automatic synchronization to $autosynccount times per day."
        $subscription.SynchronizeAutomatically = $true
        $subscription.NumberOfSynchronizationsPerDay = $autosynccount
    }

    $subscription.Save()

    RunPostInstall

    $subscription.StartSynchronization()

    Write-Host 'WSUS Sync started'
}

if (ShouldScriptRun) {
    Write-Host "Configuring WSUS"

    SetScriptRun
    InstallWSUS
    ConfigWSUSAndPerformCategorySync
    ConfigProductsForSync
    ConfigClassificationsForSync
    SetAutoApproval
    SetSynchronizationTypeAndStartFullSync
}
else {
    Write-Host "WSUS configuration script has already run. Use parameter 'Force=true' in the configuration file to force script to run again."
}