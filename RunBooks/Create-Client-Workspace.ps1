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
workflow Create-Client-Workspace
{
   
Param
     (   
        [Parameter(Mandatory=$true)]
        [String]
        $SubscriptionName,
        
        [Parameter(Mandatory=$true)]
        [String]
        $ApplicationId,
        
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
        $PersistentTags = "application_id,service_owner,application_name"
    )
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName
    
    $resourceGroupPrefix = "$($ApplicationId)$($ClusterName)$($BusinessMnemonic)rgp"
    $ManagedGroups = @()

    $ManagedGroups = InlineScript {
        $resourceGroups = @()
        $resourceGroupMap = @{}
        $tags = @{}
        $tags.Add("application_id",$Using:ApplicationId)
        $tags.Add("service_owner",$Using:ServiceOwner)
        if($Using:ApplicationName -ne $null){
            $tags.Add("application_name",$Using:ApplicationName)
        }

        $existingResourceGroups = Find-AzureRmResourceGroup
        foreach($rg in $existingResourceGroups){
            $resourceGroupMap.Add($rg.name.ToString().ToLower(), $rg)
        }
        
        For($i=1; $i -le $Using:NumberOfGroups; $i++){
            $paddedCount = $i.ToString().PadLeft(2,'0').ToLower()
            $resourceGroupName = "$($Using:resourceGroupPrefix)$($paddedCount)"
            $existingGroup = $resourceGroupMap.Item($resourceGroupName)
            #If the groups already exist. Don't try creating again.
            if($existingGroup -ne $null){
                Write-Verbose "skipping $resourceGroupName. group exists. applying tags."
                Set-AzureRMResourceGroup -Name $resourceGroupName -Tag $tags | Out-Null
                $resourceGroups += $resourceGroupName
            }else{
                Write-Verbose "creating $resourceGroupName"
                $existingGroup = New-AzureRmResourceGroup -Name $resourceGroupName.ToLower() -Location $Using:Location -Tag $tags  | Out-Null
                #Sleep before trying to apply policy. Helps to avoid unknown Race conditions.
                Start-Sleep -Seconds 5
                $resourceGroups += $resourceGroupName
            }
            
            #
        }
        return $resourceGroups
    }

    foreach($group in $ManagedGroups){
        Write-Output "enforcing tag policy for RGP: $group, SUB: $SubscriptionName"
        Manage-Propagate-Tags-Policy -ResourceGroupName $group -SubscriptionName $SubscriptionName -PersistentTags $PersistentTags -PolicyAction ADD
    }
    

}