workflow Clear-Billing-Fields
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
    
    sequence {
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
                        $isremoved = Remove-AzureRmPolicyAssignment -Name ("append"+$key+"tag") -Scope $resourceGroup.ResourceId 
                        $isremoved = Remove-AzureRmPolicyAssignment -Name ("denywithout"+$key+"tag") -Scope $resourceGroup.ResourceId 
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
                            Write-Output  "$key : $value check $r.ResourceId"
                            if($PolicyTags.Contains($key) -and !($r.Tags -eq $NULL) -and $r.tags.Contains($key)){
                                $r.tags.remove($key)
                                Write-Output  "$key : $value found $($r.ResourceId)"
                            }    
                        }    
                    $r | Set-AzureRmResource -Tags ($a=if($r.Tags -eq $NULL) { @{}} else {$r.Tags}) -Force -UsePatchSemantics
                    Write-Output  "Remove old tags $($r.tags | out-string) if any $($r.ResourceId)"
            }
                catch{
                    Write-Output  $r.ResourceId + "can't be updated"
            }
            }

        }

    }
   
}