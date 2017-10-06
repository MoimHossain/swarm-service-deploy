
[CmdletBinding()]
Param
(
    [object]$WebhookData
)

    Write-Output "Runbook Called"
    $AzureLBPIP = "<Public IP of Load balancer>"
    $Port = 5000
    # I am not using SSH key yet, therefore user name and password :(
    $RemoteUserName = "<SSH user name>"
    $RemotePassword = "<SSH password>"
    # Azure Container Registry credentials
    $ACRUserName = "<Azure Container Registry user name>"
    $ACRPassword = "<Azure container registry password>"
    # Should be a form of following
    # ?sv=2016-05-31&ss=bfqt&srt=sco&sp=rl&st=2017-10-05T16%300Z&se=2018-10-06T16%00Z&sig=%2FPO2go%3D
    $sasToken = "<Blob container SSH Token>"
    # Example: 
    # https://<Storage Account name>.blob.core.windows.net/deployment-scripts/
    $blobRoot = "<BLOB Container URL>"
    $resourceGroup = "<Resource Group name>"
    $storageAccount = "<Storage Account>"
        
    # You may not need to change these properties - unless you really need to.
    $deploymentTableName = "deployments"    
    $connectionName = "AzureRunAsConnection"
    $partitionKey = ""
    $dockerImage = ""

if ($WebHookData) {
    $WebhookBody = $WebHookData.RequestBody    
    $JsonParameters = (ConvertFrom-Json -InputObject $WebhookBody)

    $imageName = $JsonParameters.target.repository
    if([int]$imageName.IndexOf("/") -gt -1) {
        $imageName = $imageName.Substring($imageName.IndexOf("/") + 1)
    }
    $partitionKey = $imageName
    $dockerImage = $imageName
    $dockerImageFullName = ($JsonParameters.request.host + "/" + $JsonParameters.target.repository)

    try
    {
        Write-Output "Logging in to Azure..."
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName        
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint   $servicePrincipalConnection.CertificateThumbprint
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    $saContext = (Get-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount).Context
    $deploymentTable = Get-AzureStorageTable -Name $deploymentTableName -Context $saContext
    $depEntities = Get-AzureStorageTableRowByPartitionKey -table $deploymentTable –partitionKey $partitionKey | measure
    $createOrUpdate = ""

    Write-Output ("The record count: " + $depEntities.Count)
    $DepCount = $depEntities.Count
    if(0 -eq [int]$DepCount) {
        $createOrUpdate = ".create"
    } else {
        $createOrUpdate = ".update"
    }
    
    $blobUrl = $($blobRoot + $dockerImage + $createOrUpdate + $SasToken)    
    Write-Output ("URL " + $blobUrl)    
    $testC = $(Invoke-WebRequest -Uri $blobUrl -UseBasicParsing)
    $serviceComposeScript = [System.Text.Encoding]::ASCII.GetString($testC.Content)

    if (([string]::IsNullOrEmpty($serviceComposeScript)))
    {
        $errMsg = "No Blob URL" + $blobUrl
        Write-Error -Message $errMsg -ErrorAction stop        
    }

    function RunSSHCommand {
        param($CName, $UName, $Pass, $SshPort, $bashScript)
        
        $bash = [Scriptblock]::Create($bashScript)
        $secpasswd = ConvertTo-SecureString $Pass -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ($UName, $secpasswd)
        $result = Invoke-SSHCommand -ComputerName $CName -Credential $creds -Port $SshPort -Verbose -ScriptBlock $bash
        $result
        return
    }
    # Remove nodes that are down
    $baskCommand = @"
docker node rm -f `$(docker node ls --format "{{.ID}} {{.Status}}" | grep -i 'down' | awk "{print \`$1}")
"@
    RunSSHCommand -CName $AzureLBPIP -UName $RemoteUserName -Pass $RemotePassword -SshPort $Port -bashScript $baskCommand

    # Login to ACR
    $baskCommand = @"
docker login moimha.azurecr.io --username $ACRUserName --password $ACRPassword
"@
    RunSSHCommand -CName $AzureLBPIP -UName $RemoteUserName -Pass $RemotePassword -SshPort $Port -bashScript $baskCommand

    # Service CREATE or UPDATE
    $serviceComposeScript = $serviceComposeScript.Replace("[SERVICE_NAME]", $dockerImage)
    $serviceComposeScript = $serviceComposeScript.Replace("[IMAGE_NAME]", $dockerImageFullName)
    # Update Secrets - LATER
    $baskCommand = $serviceComposeScript
    $SSHResult = RunSSHCommand -CName $AzureLBPIP -UName $RemoteUserName -Pass $RemotePassword -SshPort $Port -bashScript $baskCommand
    Write-Output $SSHResult

    Add-StorageTableRow -table $deploymentTable -partitionKey $partitionKey -rowKey ([guid]::NewGuid().tostring()) -property @{"OUTPUT"=$SSHResult.ToString();"Command"=$baskCommand}

    Write-Output "Runbook executed successfully"
}
else
{     
   Write-Output "Runbook was not started from Webhook"
}


