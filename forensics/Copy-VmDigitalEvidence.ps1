<#
.SYNOPSIS
    Performs a digitial evidence capture operation on a target VM 

.DESCRIPTION
    This is designed to be run from a Linux Hybrid Runbook Worker in response to a
    digitial evidence capture request for a target VM.  It will create disk snapshots
    for all disks, copying them to immutable SOC storage, and take a SHA-256 hash and
    storing the results in your SOC Key Vault.

    This script depends on Az.Accounts, Az.Compute, Az.Storage, and Az.KeyVault being 
    imported in your Azure Automation account.
    See: https://docs.microsoft.com/en-us/azure/automation/az-modules

.EXAMPLE
    Copy-VmDigitialEvidence -SubscriptionId ffeeddcc-bbaa-9988-7766-554433221100 -ResourceGroupName rg-finance-vms -VirtualMachineName vm-workstation-001

.LINK
    https://docs.microsoft.com/azure/architecture/example-scenario/forensics/
#>

param (
    # The ID of subscription in which the target Virtual Machine is stored
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionId,

    # The Resource Group containing the Virtual Machine
    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupName,

    # The name of the target Virtual Machine
    [Parameter(Mandatory = $true)]
    [string]
    $VirtualMachineName
)

$ErrorActionPreference = 'Stop'

######################################### SOC Constants #####################################
# SOC Team Evidence Resources
$destSubId = '00112233-4455-6677-8899-aabbccddeeff'   # The subscription containing the storage account being copied to
$destRGName = 'PLACEHOLDER'                           # The Resource Group containing the storage account being copied to
$destSA = 'PLACEHOLDER'                               # The name of the storage account
$destTempShare = 'PLACEHOLDER'                        # The temporary file share mounted on the hybrid worker
$destSAContainer = 'PLACEHOLDER'                      # The name of the container within the storage account
$destKV = 'PLACEHOLDER'                               # The name of the keyvault to store a copy of the BEK in the dest subscription

$targetLinuxDir = "/mnt/$destSA/$destTempShare"       # The name of directory in which file share is mounted
$snapshotPrefix = (Get-Date).toString('yyyyMMddhhmm') # The prefix of the snapshot to be created

#############################################################################################

################################## Login session ############################################
# Connect to Azure via the Azure Automation's RunAs Account
#
# AUTHOR TODO: Replace Usage of Get-AutomationPSCredential + Connect-AzAccount
# with: Get-AutomationConnection + Connect-AzAccount.
#
# Feel free to adjust the following lines to invoke Connect-AzAccount via
# whatever mechanism your Hybrid Runbook Workers are configured to use.
# For example, for Managed Identity you can simply invoke
# Connect-AzAccount -Identity
#
# Whatever service principal is used, it must have the following permissions
#  - Create/Delete snapshots on the source subscription
#  - Read encryption key from the source subscription
#  - Read/Write access to the Storage Account on the SOC subscription
#  - Read/Write access to the Key Vault on the SOC subscription

$myCredential = Get-AutomationPSCredential -Name 'PLACEHOLDER'
$userName = $myCredential.UserName
$password = $myCredential.GetNetworkCredential().Password

$myPsCred = New-Object System.Management.Automation.PSCredential($userName, $password)

Connect-AzAccount -Credential $myPsCred

# AUTHOR TODO:
# PLEASE TRY THE FOLLOWING
# $connectionCtx = Get-AutomationConnection -Name AzureRunAsConnection
# Connect-AzAccount -ServicePrincipal -Tenant $connectionCtx.TenantID -ApplicationId $connectionCtx.ApplicationID -CertificateThumbprint $connectionCtx.CertificateThumbprint
# or Set this up even better to use Managed Identity and then you'd only need to do
# Connect-AzAccount -Identity

############################# Snapshot the OS disk of target VM ##############################
Write-Output "#################################"
Write-Output "Snapshot the OS Disk of target VM"
Write-Output "#################################"

Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName

$disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name
$snapshot = New-AzSnapshotConfig -SourceUri $disk.Id -CreateOption Copy -Location $vm.Location
$snapshotName = $snapshotPrefix + "-" + $disk.name
New-AzSnapshot -ResourceGroupName $ResourceGroupName -Snapshot $snapshot -SnapshotName $snapshotname


##################### Copy the OS snapshot from source to file share and blob container ########################
Write-Output "#################################"
Write-Output "Copy the OS snapshot from source to file share and blob container"
Write-Output "#################################"

$snapSasUrl = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName -DurationInSecond 72000 -Access Read
Get-AzSubscription -SubscriptionId $destSubId | Set-AzContext
$targetStorageContext = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSA).Context

Start-AzStorageFileCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestShareName $destTempShare -DestContext $targetStorageContext -DestFilePath $SnapshotName -Force

Get-AzStorageFileCopyState -Context $targetStorageContext -ShareName $destTempShare -FilePath $SnapshotName -WaitForComplete

$diskpath = "$targetLinuxDir/$snapshotName"
    
$hashfull = Invoke-Expression -Command "sha256sum $diskpath"
$hash = $hashfull.split(" ")[0]

Write-Output "Computed SHA-256: $hash"

Start-AzStorageBlobCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestContainer $destSAContainer -DestContext $targetStorageContext -DestBlob $SnapshotName -Force


#################### Copy the OS BEK to the SOC Key Vault  ###################################
$BEKurl = $disk.EncryptionSettingsCollection.EncryptionSettings.DiskEncryptionKey.SecretUrl
Write-Output "#################################"
Write-Output "Disk Encryption Secret URL: $BEKurl"
Write-Output "#################################"
if ($BEKurl) {
    $sourcekv = $BEKurl.Split("/")
    $BEK = Get-AzKeyVaultSecret -VaultName  $sourcekv[2].split(".")[0] -Name $sourcekv[4] -Version $sourcekv[5]
    Write-Output "Key value: $BEK"
    Set-AzKeyVaultSecret -VaultName $destKV -Name $SnapshotName -SecretValue $BEK.SecretValue -ContentType "BEK" -Tag $BEK.Tags
}


######## Copy the OS disk hash value in key vault and delete disk in file share ##################
Write-Output "#################################"
Write-Output "OS disk - Put hash value in Key Vault"
Write-Output "#################################"
$secret = ConvertTo-SecureString -String $hash -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $destKV -Name "$SnapshotName-sha256" -SecretValue $secret

Remove-AzStorageFile -ShareName $destTempShare -Path $SnapshotName -Context $targetStorageContext


############################ Snapshot the data disks, store hash and BEK #####################
$dsnapshotList = @()

foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
    $ddisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name
    $dsnapshot = New-AzSnapshotConfig -SourceUri $ddisk.Id -CreateOption Copy -Location $vm.Location
    $dsnapshotName = $snapshotPrefix + "-" + $ddisk.name
    $dsnapshotList += $dsnapshotName
    Write-Output "Snapshot data disk name: $dsnapshotName"
    New-AzSnapshot -ResourceGroupName $ResourceGroupName -Snapshot $dsnapshot -SnapshotName $dsnapshotName
    
    Write-Output "#################################"
    Write-Output "Copy the Data Disk $dsnapshotName snapshot from source to blob container"
    Write-Output "#################################"

    $dsnapSasUrl = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotName -DurationInSecond 72000 -Access Read
    $targetStorageContext = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSA).Context

    Start-AzStorageFileCopy -AbsoluteUri $dsnapSasUrl.AccessSAS -DestShareName $destTempShare -DestContext $targetStorageContext -DestFilePath $dsnapshotName  -Force
    
    Get-AzStorageFileCopyState -Context $targetStorageContext -ShareName $destTempShare -FilePath $dsnapshotName -WaitForComplete

    $ddiskpath = "$targetLinuxDir/$dsnapshotName"
    
    $dhashfull = Invoke-Expression -Command "sha256sum $ddiskpath"
    $dhash = $dhashfull.split(" ")[0]

    Write-Output "Computed SHA-256: $dhash"

    Start-AzStorageBlobCopy -AbsoluteUri $dsnapSasUrl.AccessSAS -DestContainer $destSAContainer -DestContext $targetStorageContext -DestBlob $dsnapshotName -Force
    
    $BEKurl = $ddisk.EncryptionSettingsCollection.EncryptionSettings.DiskEncryptionKey.SecretUrl
    Write-Output "#################################"
    Write-Output "Disk Encryption Secret URL: $BEKurl"
    Write-Output "#################################"
    if ($BEKurl) {
        $sourcekv = $BEKurl.Split("/")
        $BEK = Get-AzKeyVaultSecret -VaultName  $sourcekv[2].split(".")[0] -Name $sourcekv[4] -Version $sourcekv[5]
        Write-Output "Key value: $BEK"
        Write-Output "Secret name: $dsnapshotName"
        Set-AzKeyVaultSecret -VaultName $destKV -Name $dsnapshotName -SecretValue $BEK.SecretValue -ContentType "BEK" -Tag $BEK.Tags
    }
    
    Write-Output "#################################"
    Write-Output "Data disk - Put hash value in Key Vault"
    Write-Output "#################################"
    $Secret = ConvertTo-SecureString -String $dhash -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $destKV -Name "$dsnapshotName-sha256" -SecretValue $Secret

    Remove-AzStorageFile -ShareName $destTempShare -Path $dsnapshotName -Context $targetStorageContext
}


################################## Delete all source snapshots ###############################
Get-AzStorageBlobCopyState -Blob $snapshotName -Container $destSAContainer -Context $targetStorageContext -WaitForComplete
foreach ($dsnapshotName in $dsnapshotList) {
    Get-AzStorageBlobCopyState -Blob $dsnapshotName -Container $destSAContainer -Context $targetStorageContext -WaitForComplete
}

Revoke-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName
Remove-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotname -Force
foreach ($dsnapshotName in $dsnapshotList) {
    Revoke-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotName
    Remove-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotname -Force
}