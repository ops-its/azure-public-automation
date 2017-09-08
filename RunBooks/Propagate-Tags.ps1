<#
.SYNOPSIS
    Propagate tags on nested resources.
.DESCRIPTION
    This runbook sets policies on a resource group to persist specific tags to all nested resources.
    See: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-policy-tags

.PARAMETER ResourceGroupName
   Required

.PARAMETER SubscriptionName
   Required

.PARAMETER PersistentTags
    Required
    Comma-separated list of tags to persist.

.NOTES
   AUTHOR: Dimiter Todorov
   LASTEDIT: September 8, 2017
#>
workflow Propagate-Tags
{
Param
    (   
        [Parameter(Mandatory=$true)]
        [String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [String]
        $SubscriptionName,
        [Parameter(Mandatory=$true)]
        [String]
        $PersistentTags
    )
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName
    
    InlineScript {
        $appendpolicy = Get-AzureRmPolicyDefinition | Where-Object {$_.Name -eq '2a0e14a6-b0a6-4fab-991a-187a4f81c498'}
        $denypolicy = Get-AzureRmPolicyDefinition | Where-Object {$_.Name -eq '1e30110a-5ceb-460c-a204-c1c3969c6d62'}
        $createdPolicies = @()
        $PolicyTags = $Using:PersistentTags
        $PolicyTags = $PolicyTags.Split(",").Trim()
        
        $resourceGroup = Get-AzureRmResourceGroup -Name $Using:ResourceGroupName
        $tags = $resourceGroup.Tags
        foreach($tag in $tags.GetEnumerator()){
            $key = $tag.Name
            $value = $tag.Value
            $appendPolicyName = "append"+$key+"tag"
            $denyPolicyName = "denywithout"+$key+"tag"
            if($PolicyTags.Contains($key)){
                $existingAppendPolicy = Get-AzureRmPolicyAssignment -Scope $resourceGroup.ResourceId -Name $appendPolicyName
                $existingDenyPolicy = Get-AzureRmPolicyAssignment -Scope $resourceGroup.ResourceId -Name $denyPolicyName
                
                #Check and create append policy if it does not exist.
                if($existingAppendPolicy -eq $null){
                    $createdPolicies += New-AzureRmPolicyAssignment -Name $appendPolicyName -PolicyDefinition $appendpolicy -Scope $resourceGroup.ResourceId `
                    -PolicyParameterObject @{tagName=$key;tagValue=$value}
                    Write-Output "[SUCCESS] Persisting Tag $key = $value on ResourceGroup $($resourceGroup.ResourceGroupName)"
                }else{
                    Write-Output "[INFO] Policy $($existingAppendPolicy.Name) already exists on $($resourceGroup.ResourceGroupName)"
                }
                
                #Check and create deny policy if it does not exist.
                if($existingDenyPolicy -eq $null){
                    $createdPolicies += New-AzureRmPolicyAssignment -Name $appendPolicyName -PolicyDefinition $denypolicy -Scope $resourceGroup.ResourceId `
                    -PolicyParameterObject @{tagName=$key;tagValue=$value}
                    Write-Output "[SUCCESS] Persisting Tag $key = $value on ResourceGroup $($resourceGroup.ResourceGroupName)"
                }else{
                    Write-Output "[INFO] Policy $($existingDenyPolicy.Name) already exists on $($resourceGroup.ResourceGroupName)"
                }
                
            }else{
                Write-Output "[IGNORE] $key is not part of the PersistentTags"
            }
            $existingAppendPolicy = $null
            $existingDenyPolicy = $null
        }
    }
    $createdPolicies
}