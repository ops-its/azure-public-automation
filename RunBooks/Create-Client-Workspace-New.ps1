 <#
.SYNOPSIS
    Create Client workspaces for ITS Shared Environment

.DESCRIPTION
    This workflow creates resource groups for client environments within Azure.
    All resource groups are created in the same location.
    The script is idempotent and can be re-run multiple times. It will skip any exsiting groups that match the name.
    e.g.
    For example, using the following parameters: -ApplicationId "00001" -ClusterName "cscc" -BusinessMnemonic "ist01" -NumberOfGroups 4
    Results in a group name of 00001csccist01rgp[xx] with xx being incremented depending on the number of groups required.
    If Groups 01-03 exist, only one additional group will be created. 00001csccist01rgp04

.PARAMETER SubscriptionName
   Required

.PARAMETER ApplicationId
   Required

.PARAMETER ClusterName
   Required

.PARAMETER BusinessMnemonic
   Required

.PARAMETER NumberOfGroups
   Required
   Number of groups to ensure within the Subscription.

.PARAMETER Location
    Optional
    Default to canadacentral

.PARAMETER ServiceOwner
    Optional
    Default to ITS

.PARAMETER ApplicatioName
    Optional
    This will be added as a tag on the resource group with key application_name
           
.PARAMETER PersistentTags
    Optional
    Comma-separated list of tags to persist on child resources.

.NOTES
   AUTHOR: Dimiter Todorov
   LASTEDIT: September 11, 2017
#>
   
Param
    (   
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionName,
        
    [Parameter(Mandatory=$true)]
    [String]
    $ClusterApplicationId,
        
    [Parameter(Mandatory=$true)]
    [String]
    $ClusterName,
        
    [Parameter(Mandatory=$true)]
    [String]
    $BusinessMnemonic,

    [Parameter(Mandatory=$true)]
    [int]
    [string]$NumberOfGroups,

    [Parameter(Mandatory=$false)]
    [String]
    $Location = "canadacentral",

    [Parameter(Mandatory=$false)]
    [String]
    $ServiceOwner = "ITS",

    [Parameter(Mandatory=$false)]
    [String]
    $ApplicationName,

    [Parameter(Mandatory=$false)]
    [String]
    $PersistentTags = "application_id,service_owner,application_name",
    
    
    [Parameter(Mandatory=$false)]
    [boolean]
    $RunInAzureAutomation=$true,

    [Parameter(Mandatory=$false)]
    [String]
    $TenantId,

    [Parameter(Mandatory=$false)]
    [String]
    $ApplicationId,

    [Parameter(Mandatory=$false)]
    [String]
    $AccessToken

)

if($RunInAzureAutomation){
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
}else{
    $appToken = ConvertTo-SecureString $AccessToken -AsPlainText -Force
    $azureCredentials = New-Object System.Management.Automation.PSCredential ($ApplicationId, $appToken)
    Add-AzureRmAccount -ServicePrincipal -Credential $azureCredentials -TenantId $TenantId
}
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#TODO: Make this dynamic based on naming convention
$locationCode="c"
$resourceGroupPrefix = "$($ClusterApplicationId)$($ClusterName)$($locationCode)$($BusinessMnemonic)rgp"
$ManagedGroups = @()


$resourceGroups = @()
$resourceGroupMap = @{}
$tags = @{}
$tags.Add("application_id",$ClusterApplicationId)
$tags.Add("service_owner",$ServiceOwner)
if($ApplicationName -ne $null){
    $tags.Add("application_name",$ApplicationName)
}

$existingResourceGroups = Find-AzureRmResourceGroup
foreach($rg in $existingResourceGroups){
    $resourceGroupMap.Add($rg.name.ToString().ToLower(), $rg)
}
        
For($i=1; $i -le $NumberOfGroups; $i++){
    $paddedCount = $i.ToString().PadLeft(2,'0').ToLower()
    $resourceGroupName = "$($resourceGroupPrefix)$($paddedCount)"
    $existingGroup = $resourceGroupMap.Item($resourceGroupName)
    #If the groups already exist. Don't try creating again.
    if($existingGroup -ne $null){
        Write-Host "skipping $resourceGroupName. group exists. applying tags."
        Set-AzureRMResourceGroup -Name $resourceGroupName -Tag $tags | Out-Null
        $resourceGroups += $resourceGroupName
    }else{
        Write-Host "creating $resourceGroupName"
        $existingGroup = New-AzureRmResourceGroup -Name $resourceGroupName.ToLower() -Location $Location -Tag $tags  | Out-Null
        #Sleep before trying to apply policy. Helps to avoid unknown Race conditions.
        Start-Sleep -Seconds 5
        $resourceGroups += $resourceGroupName
    }
}

foreach($group in $resourceGroups){
    Write-Output "enforcing tag policy for RGP: $group, SUB: $SubscriptionName"
    if($RunInAzureAutomation){
        .\Manage-Propagate-Tags-Policy-New -ResourceGroupName $group -SubscriptionName $SubscriptionName `
            -PersistentTags $PersistentTags -PolicyAction ADD
    }else{
        .\Manage-Propagate-Tags-Policy-New -ResourceGroupName $group -SubscriptionName $SubscriptionName `
            -PersistentTags $PersistentTags -PolicyAction ADD `
            -TenantId $tenantId -ApplicationId $appId -AccessToken $token -RunInAzureAutomation $false

    }
}
