workflow Update-Resource-Tags
{
    param
    (
        [Parameter(Mandatory=$true)]
        [String]
        $AzureResourceGroup,
        [Parameter(Mandatory=$false)]
        [String]
        $PersistentTags = "application_id"
    )
    
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
  
    InlineScript {
        $PolicyTags = $Using:PersistentTags
        $PolicyTags = $PolicyTags.Split(",").Trim()
        
        $resourceGroup = Get-AzureRmResourceGroup -Name $Using:AzureResourceGroup
        $tags = $resourceGroup.Tags
        $resources = Find-AzureRmResource -ResourceGroupName $Using:AzureResourceGroup 
        
        foreach($tag in $tags.GetEnumerator()){
            $key = $tag.Name
            $value = $tag.Value

            if($PolicyTags.Contains($key)){
                Remove-AzureRmPolicyAssignment -Name ("append"+$key+"tag") -Scope $resourceGroup.ResourceId 
                Remove-AzureRmPolicyAssignment -Name ("denywithout"+$key+"tag") -Scope $resourceGroup.ResourceId 
                Write-Output "[SUCCESS] removing policy for $key = $value on ResourceGroup $resourceGroup"
            }else{
                Write-Output "[IGNORE] $key is not part of the PersistentTags"
            }
        }

        foreach($r in $resources)
        {
            try{
                    foreach($tag in $tags.GetEnumerator()){
                        $key = $tag.Name
                        $value = $tag.Value
                         Write-Output  $key + ":" + $value + " check"
                        if($PolicyTags.Contains($key) -and !($r.Tags -eq $NULL) -and $r.tags.Contains($key)){
                            $r.tags.remove($key)
                            Write-Output  $key + ":" + $value + " found"
                        }    
                    }    
                $r | Set-AzureRmResource -Tags ($a=if($r.Tags -eq $NULL) { @{}} else {$r.Tags}) -Force -UsePatchSemantics
           }
            catch{
                Write-Output  $r.ResourceId + "can't be updated"
           }
        }

    }

    $createdPolicies = Propagate-Billing-Fields –AzureResourceGroup $AzureResourceGroup -PersistentTags $PersistentTags

    InlineScript {
        $resources = Find-AzureRmResource -ResourceGroupName $Using:AzureResourceGroup 
       foreach($r in $resources)
        {
                try{
                    $r | Set-AzureRmResource -Tags ($a=if($r.Tags -eq $NULL) { @{}} else {$r.Tags}) -Force -UsePatchSemantics
            }
                catch{
                    Write-Output  $r.ResourceId + "can't be updated with policy"
            }
        }
    }
   
}