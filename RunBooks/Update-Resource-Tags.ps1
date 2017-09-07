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
    sequence {
        $createdPolicies = Propagate-Billing-Fields –AzureResourceGroup $AzureResourceGroup -PersistentTags $PersistentTags

        InlineScript {
            $resources = Find-AzureRmResource -ResourceGroupName $Using:AzureResourceGroup 
        foreach($r in $resources)
            {
                    try{
                        $r | Set-AzureRmResource -Tags ($a=if($r.Tags -eq $NULL) { @{}} else {$r.Tags}) -Force -UsePatchSemantics
                        Write-Output  "Update with new policy $($r.ResourceId)"
                }
                    catch{
                        Write-Output  $r.ResourceId + "can't be updated with policy"
                }
            }
        }
    }
   
}