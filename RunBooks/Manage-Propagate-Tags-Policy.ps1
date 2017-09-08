<#
.SYNOPSIS
    Manage propagating tags on nested resources.

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

.PARAMETER PolicyAction
    Required
    One of ADD/REMOVE/RESET.
    Reset will remove and recreate the policy assignment.

.NOTES
   AUTHOR: Dimiter Todorov
   LASTEDIT: September 8, 2017
#>
workflow Manage-Propagate-Tags-Policy
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
        $PersistentTags,

        [Parameter(Mandatory=$true)]
        [ValidateSet("ADD", "REMOVE", "RESET")]
        [string]$PolicyAction
    )

    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName

    $CreatedPolicies = InlineScript {
        $CreatedPolicies = @()
        $PolicyAction = $Using:PolicyAction
        $PolicyTags = $Using:PersistentTags
        $PolicyTags = $PolicyTags.Split(",").Trim()

        # TODO: Is it safe having this hard-coded to UUIDs?
        $appendpolicy = Get-AzureRmPolicyDefinition | Where-Object {$_.Name -eq '2a0e14a6-b0a6-4fab-991a-187a4f81c498'}
        $denypolicy = Get-AzureRmPolicyDefinition | Where-Object {$_.Name -eq '1e30110a-5ceb-460c-a204-c1c3969c6d62'}

        $resourceGroup = Get-AzureRmResourceGroup -Name $Using:ResourceGroupName
        foreach($tag in $PolicyTags){
            $key = $tag
            
            $appendPolicyName = "append"+$key+"tag"
            $denyPolicyName = "denywithout"+$key+"tag"
            
            $policyMap = @{
                $appendPolicyName = $appendpolicy
                $denyPolicyName = $denypolicy
            }

            foreach($policyName in $policyMap.Keys){
                #If tag does not exist, but action is REMOVE, clean out the policies. Otherwise warn.
                if($resourceGroup.Tags.Item($tag) -eq $null){
                    if($PolicyAction -eq "REMOVE"){
                        Remove-AzureRmPolicyAssignment -Name $policyName -Scope $resourceGroup.ResourceId
                        Write-Output "[SUCCESS] removing $policyName on $($resourceGroup.ResourceGroupName)"
                    }else{
                        Write-Warning "[WARN] Cannot $PolicyAction for Tag $tag on RG $($resourceGroup.ResourceGroupName)"
                    }
                }else{
                    $value = $resourceGroup.Tags.Item($tag)
                    try{
                        $existingPolicy = Get-AzureRmPolicyAssignment -Scope $resourceGroup.ResourceId -Name $policyName -ErrorAction SilentlyContinue -WarningAction Ignore
                    }catch{
                        $existingPolicy = $null
                    }
                    if($existingPolicy -ne $null){
                        if($PolicyAction -eq "RESET"-or ($PolicyAction -eq "REMOVE")){
                            Remove-AzureRmPolicyAssignment -Name $policyName -Scope $resourceGroup.ResourceId
                            Write-Output "[SUCCESS] removing $policyName on $($resourceGroup.ResourceGroupName)"
                            $existingPolicy = $null
                            Start-Sleep -Seconds 5
                        }else{
                            Write-Output "[INFO] policy $($existingPolicy.Name) already exists on $($resourceGroup.ResourceGroupName)"
                        }
                    }
                    if($existingPolicy -eq $null){
                        if($PolicyAction -eq "ADD" -or $PolicyAction -eq "RESET"){
                            $CreatedPolicies += New-AzureRmPolicyAssignment -Name $policyName -PolicyDefinition $policyMap.Item($policyName) -Scope $resourceGroup.ResourceId `
                                -PolicyParameterObject @{tagName=$key;tagValue=$value}
                            Write-Output "[SUCCESS] applying $policyName on $($resourceGroup.ResourceGroupName)"
                        }    
                    }
                }
                $existingPolicy = $null
            }
            
        }
        $CreatedPolicies
    }
    $CreatedPolicies
}