param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory=$true)]        
        [string]$VMSize,
        [Parameter(Mandatory=$true)]        
        [string]$Location,
        [Parameter(Mandatory=$true)]        
        [string]$StorageAccountName,
        [Parameter(Mandatory=$true)]        
        [string]$VMName  

      )
 
    Login-AzureRmAccount


[array]$AzureLocations=Get-AzureRmLocation | sort Location | Select Location



$isRGCreated=New-AzureRmResourceGroup -Name $ResourceGroup -Location $Location -Force

if(-not $isRGCreated)
{
    Write-Error 'Failed to create Resource Group. Please retry with different name'
    return
}

# Create Storage Accoun

$isStorageAccountAvailable=Get-AzureRmStorageAccountNameAvailability $StorageAccountName


$VMStorageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccountName.ToLower() -SkuName "Standard_LRS" -Kind "Storage" -Location $Location

if(-not $VMStorageAccount)
{
    Write-Error "Failed to create storage account $($StorageAccountName.ToLower())"
    $VMStorageAccount=Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccountName.ToLower()
    Write-Verbose 'Checking storage account already exist..'
    if(-not $VMStorageAccount)
    {
        Write-Error "storage account $($StorageAccountName.ToLower()) not exist.exiting"
        return
    }
}

[string]$ResourcePrefix=$VMName
# Create Virtual Network

$mySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "$($ResourcePrefix)-Subnet" -AddressPrefix 10.0.0.0/24
$myVnet = New-AzureRmVirtualNetwork -Name "$($ResourcePrefix)-Vnet" -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix 10.0.0.0/16 -Subnet $mySubnet -Force

#Create public IP Address

$myPublicIp = New-AzureRmPublicIpAddress -Name "$($ResourcePrefix)-PublicIp" -ResourceGroupName $ResourceGroup -Location $Location -AlLocationMethod Dynamic -Force
$myNIC = New-AzureRmNetworkInterface -Name "$($ResourcePrefix)-NIC" -ResourceGroupName $ResourceGroup -Location $Location -SubnetId $myVnet.Subnets[0].Id -PublicIpAddressId $myPublicIp.Id -Force


# Create Virtual Machine
$cred = Get-Credential -Message "Type the name and password of the local administrator account." 

#Example VM Sizes are : Standard_DS1_v2
$myVm = New-AzureRmVMConfig -VMName "$($ResourcePrefix)-VM" -VMSize $VMSize

$myVM = Set-AzureRmVMOperatingSystem -VM $myVM -Windows -ComputerName "$($ResourcePrefix)-VM" -Credential $cred -ProvisionVMAgent -EnableAutoUpdate

$myVM = Set-AzureRmVMSourceImage -VM $myVM -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2012-R2-Datacenter" -Version "latest"

$myVM = Add-AzureRmVMNetworkInterface -VM $myVM -Id $myNIC.Id

$blobPath = "vhds/$($ResourcePrefix)OsDisk1.vhd"

$osDiskUri = $VMStorageAccount.PrimaryEndpoints.Blob.ToString() + $blobPath

$vm = Set-AzureRmVMOSDisk -VM $myVM -Name $VMName -VhdUri $osDiskUri -CreateOption fromImage

New-AzureRmVM -ResourceGroupName $ResourceGroup -Location $Location -VM $myVM