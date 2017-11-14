Param
(
	[Parameter (Mandatory= $true)]
	[String] $subscription_id,

	[Parameter (Mandatory= $true)]
	[System.Data.SqlClient.SqlConnection] $DatabaseConnection,

	[Parameter (Mandatory= $true)]
	[String] $workspaceresourcegroup,

	[Parameter (Mandatory= $true)]
	[String] $workspacename
)

$workspace=Get-AzureRmOperationalInsightsWorkspace -Name $workspacename -ResourceGroupName $workspaceresourcegroup 
$workspaceId = $workspace.CustomerId
$workspaceKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey

$vms = Get-AzureRmVM  

$PublicSettings = @{"workspaceId" = $workspaceId}
$ProtectedSettings = @{"workspaceKey" = $workspaceKey}

$sqlDeleteCmd = "delete from [dbo].[UnmanagedClientVm] where subscriptionId = @subscription_id"
$deleteCmd=new-object system.Data.SqlClient.SqlCommand($sqlDeleteCmd, $DatabaseConnection) 
$subscription_delete_param=$deleteCmd.Parameters.Add("@subscription_id" , [System.Data.SqlDbType]::NVarChar)
$subscription_delete_param.Value = $subscription_id.ToString();
$deleteCmd.ExecuteNonQuery();

$sqlInsertCmd = "insert into [dbo].[UnmanagedClientVm] values(@subscription_id, @vm_name, @workspace_id)"
$sqlInsertCmd
$insertCmd=new-object system.Data.SqlClient.SqlCommand($sqlInsertCmd, $DatabaseConnection) 
$subscription_param=$insertCmd.Parameters.Add("@subscription_id" , [System.Data.SqlDbType]::NVarChar)
$vm_name_param=$insertCmd.Parameters.Add("@vm_name" , [System.Data.SqlDbType]::NVarChar)
$workspace_id_param=$insertCmd.Parameters.Add("@workspace_id" , [System.Data.SqlDbType]::NVarChar)

$sqlUpdateCmd = "update [dbo].[UnmanagedClientVm] set worspaceId = @workspace_id where subscriptionId = @subscription_id and vmName = @vm_name"
$sqlUpdateCmd
$updateCmd=new-object system.Data.SqlClient.SqlCommand($sqlUpdateCmd, $DatabaseConnection) 
$subscription_update_param=$updateCmd.Parameters.Add("@subscription_id" , [System.Data.SqlDbType]::NVarChar)
$vm_name_update_param=$updateCmd.Parameters.Add("@vm_name" , [System.Data.SqlDbType]::NVarChar)
$workspace_id_update_param=$updateCmd.Parameters.Add("@workspace_id" , [System.Data.SqlDbType]::NVarChar)

foreach ($vm in $vms) { 
        write-output $vm.name

        # Call Prepare after setting the Commandtext and Parameters.
		$subscription_name=Get-AzureRmSubscription -SubscriptionID $subscription_id | select -expandProperty name
        $subscription_param.Value = $subscription_name.ToString();
        $vm_name_param.Value = $vm.name;
        $workspace_id_param.Value = "-1";
        $insertCmd.ExecuteNonQuery();

      
   $location = $vm.Location
   $vmdet = Get-AzureRMVM -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname -Status
   $vmpowerstatus = $vmdet.Statuses.Code | Where-Object {$_ -Match 'PowerState'}
   $vmdisplaytatus = $vmdet.Statuses.DisplayStatus | Where-Object {$_ -Match 'Provisioning'}
   if ($vmpowerstatus -eq 'PowerState/running' -And $vmdisplaytatus -eq 'Provisioning succeeded' ) { 
		if ($vm.StorageProfile.OsDisk.OsType -eq 'Windows') {
				$vmExtensionType = 	"MicrosoftMonitoringAgent"
				} elseif ($vm.StorageProfile.OsDisk.OsType -eq 'Linux') {
				$vmExtensionType = 	"OmsAgentForLinux"
				} else {
				write-output "$($vmdet.name) - non-Windows and non-Linux [$($vm.StorageProfile.OsDisk.OsType)].Doing Nothing"
				continue;
				}				
        # re-read the VM to get extensiohn name and type populated
        $vm = Get-AzureRMVM -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname
		$extension = ($vm.extensions | where-object {$_.VirtualMachineExtensionType -match $vmExtensionType } )
        write-output "Extension found $($extension.Name)"
			if ($extension) {
				$extdet = Get-AzureRMVMExtension -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname -Name $extension.Name
				if($extension.Name -eq 'OMSExtension') {
                    $current_workspace = $extdet.PublicSettings.Split([Environment]::NewLine)[2];
					if ($current_workspace.contains($workspaceId)) {
    					write-output "$($vmdet.name) - is already in the correct workspace [$workspacename]"	
                        $subscription_update_param.Value = $subscription_name.ToString();
                        $vm_name_update_param.Value = $vm.name;
						$workspacename = Get-AzureRmOperationalInsightsWorkspace | Where-Object CustomerId -eq $workspaceId | select -expandproperty name
                        $workspace_id_update_param.Value = $workspacename.ToString();
                        $updateCmd.ExecuteNonQuery();                        
					    continue; # Move to next VM processing. 
					} else {
                        write-output "$$($vmdet.name) - current workspace [$current_workspace]. Need [$workspaceId]"
						$workspaceId = $current_workspace.split(':')[1].Replace('"',"").Trim(',').Trim()
						$workspacename = Get-AzureRmOperationalInsightsWorkspace | Where-Object CustomerId -eq $workspaceId | select -expandproperty name
						$subscription_update_param.Value = $subscription_name.ToString();
						$vm_name_update_param.Value = $vm.name;
						$workspace_id_update_param.Value = $workspacename.ToString();
						$updateCmd.ExecuteNonQuery(); 
                    }
                }    
				write-output "$$($vmdet.name) - removing $vmExtensionType extention with name $($extension.Name) and workspace [$current_workspace]"
				Remove-AzureRMVMExtension -VMname $vm.name -ResourceGroupName $vm.resourcegroupname -Name $extension.Name -force
			}
            <#
            	Now we have running  VM without OMS extension. 
                Lets attach VM to correct workspace. 
            #>                
			Set-AzureRMVMExtension -VMname $vm.name -ResourceGroupName $vm.resourcegroupname -Publisher 'Microsoft.EnterpriseCloud.Monitoring' -ExtensionType $vmExtensionType -ExtensionName 'OMSExtension' -TypeHandlerVersion 1.0 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $location 
			write-output "For machine $($vmdet.name) the extensions is/are $($extension.Name)"
            $extdet1 = Get-AzureRMVMExtension -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname -Name $extension.Name
			$current_workspace1 = $extdet1.PublicSettings.Split([Environment]::NewLine)[2]
			$workspaceId = $current_workspace1.split(':')[1].Replace('"',"").Trim(',').Trim()
			$workspacename = Get-AzureRmOperationalInsightsWorkspace | Where-Object CustomerId -eq $workspaceId | select -expandproperty name
			$subscription_update_param.Value = $subscription_name.ToString();
			$vm_name_update_param.Value = $vm.name;
			$workspace_id_update_param.Value = $workspacename.ToString();
			$updateCmd.ExecuteNonQuery(); 
		} 
	else {
			write-output "$($vmdet.name) - not running. VM status[$vmpowerstatus] and VM DisplayStatus[$vmdisplaytatus]"
	}	
    
}   
