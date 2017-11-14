<#
Param
(
	[Parameter (Mandatory= $true)]
	[String] $workspaceresourcegroup,

	[Parameter (Mandatory= $true)]
	[String] $workspacename
)
#>
Get-Date
$StartTmM = (Get-Date).Minute
$Conn = Get-AutomationConnection -Name AzureRunAsConnection

Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

$servername="itsmgmtsql"
$DB="itsmgmtdb"

$myCredential = Get-AutomationPSCredential -Name 'management-db-credential' 
$userName = $myCredential.UserName 
$securePassword = $myCredential.Password 
$password = $myCredential.GetNetworkCredential().Password

$DatabaseConnection = New-Object System.Data.SqlClient.SqlConnection
$DatabaseConnection.ConnectionString = "Server=tcp:itsmgmtsql.database.windows.net,1433;Initial Catalog=itsmgmtdb;Persist Security Info=False;User ID=$userName;Password=$password;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$DatabaseConnection.Open();
Write-Output “CONNECTION OPENED”

# Define the SQL command to run. In this case we are getting the number of rows in the table 
$Cmd=new-object system.Data.SqlClient.SqlCommand("select clientId, subscriptionName, WorkspaceResourceGroup, workspaceName from [dbo].[UnmanagedClientConfig]", $DatabaseConnection) 
$Cmd.CommandTimeout=120 

# Execute the SQL command 
$Ds=New-Object system.Data.DataSet 
$Da=New-Object system.Data.SqlClient.SqlDataAdapter($Cmd) 
[void]$Da.fill($Ds) 

# Output the count 
#Write-Output “Subscription selected”
#$Ds.Tables[0].subscription_id
#$subscription_array = $Ds.Tables[0].subscription_id
$Result = $Ds.Tables[0]

foreach ($Record in $Result.Rows) {
    write-Output "Subscriptionname value is : $($Record[1])"
    write-Output "Workspace_resource_group value is : $($Record[2])"
    write-Output "Workspace Name value is : $($Record[3])"
    $subscriptionname = $Record[1].replace(' ' , '')
    $subscriptionid = Get-AzureRmSubscription -SubscriptionName $subscriptionname | select -expandProperty SubscriptionId 
    $workspaceresourcegroup = $Record[2].replace(' ' , '')
    $workspacename = $Record[3].replace(' ' , '')
    Set-AzureRmContext -SubscriptionId $subscriptionid
    .\join-oms-workspace.ps1 $subscriptionid $DatabaseConnection $workspaceresourcegroup $workspacename
}
Get-Date
$EndTmM = (Get-Date).Minute
Write-Output "This script took $($EndTmM - $StartTmM) minutes to run"

#foreach ($subscriptionid in $subscription_array) {
#    Set-AzureRmContext -SubscriptionId $subscriptionid
#    .\join-oms-workspace.ps1 $subscriptionid $DatabaseConnection $workspaceresourcegroup $workspacename
#}


