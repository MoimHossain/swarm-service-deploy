## What is it?

This [Azure Automation Runbook](https://azure.microsoft.com/en-us/blog/azure-automation-runbook-management/) allows deploying  **docker services** into a docker swarm.


![alt text](https://i.imgur.com/YjyotNL.png)


## How it does so?
The idea is that a Build Pipeline will push an image to a private azure container registry and a webhook will trigger this automation runbook to deploy that service **securely** into the cluster. The build pipeline (which often runs on an on-prem network) doesn't require to SSH (remote access) to **swarm manager**s running on Azure virtual machines.

## Setup

1. Create a runbook "Deploy-Service" in Azure automation account (from the portal). 
2. Copy the web hook trigger URL and add it to the webhook triggers in your Azure Container Registry.
3. Create a Storage Account
4. Create a BLOB container (example __deployment-scripts__)
5. Create a Table (example __deployments__)
6. Create two text files in notepad that contains the command to deploy the service.

An example, let's say we have the container image __"feedback-service"__.
- Create a text file named __"feedback-service.create"__
- The file should contain the docker service create command with following format:
```
docker service create `
 --with-registry-auth `
 --replicas 1 `
 --name [SERVICE_NAME] `
 [IMAGE_NAME] `
 -p 9009:9009 `
 -v /var/run/docker.sock:/var/run/docker.sock 
```

Notice that **[SERVICE_NAME]** and **[IMAGE_NAME]** without specifying the actual values. The runbook will replace them before deployment based on the container image from container registry.

- Create a file named __"feedback-service.update"__
The content follows the sample principle as above:
```
docker service update `
--with-registry-auth ` 
--force `
--update-parallelism 1 `
--update-delay 30s `
--replicas 4 `
[SERVICE_NAME] `
--image [IMAGE_NAME]
```
7. Please upload these two files into the BLOB container you have created in step 4.

8. Copy the content from [**deploy-runbook.ps1**](/deploy-runbook.ps1) into the runbook code in Azure Portal.
9. Edit the file providing the correct credentials and URLs that are appropriate to your subscription and storage accounts.
10. Publish the runbook and you are Done! 

At this point your runbook should deploy everytime you push a new image for the service we have configure above. It will also log all the deployments into the table storage - as an operation log.

## Explanation of the parameters in runbook:

- $AzureLBPIP: The public IP address to your Azure Load Balancer. 
- $Port: The SSH port to the master.
- $RemoteUserName: The SSH user name 
- $RemotePassword: The SSH password

- $ACRUserName: The user name to access the Azure Container Registry
- $ACRPassword: The password for registry


- $sasToken: The SAS token to the BLOB container with **READ** access.
- $blobRoot: The URL of the BLOB container
- $resourceGroup: The resource group where the storage account was created. (Note, this indeed can be any storage account and any subscription, can be a different one than the subscription that run the swarm cluster. Only requirement is to keep the automation account and storage account into the same subscription.)
- $storageAccount: The name of the storage account.

### Thanks!
