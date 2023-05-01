#!/bin/bash

##parameters to script
prefix=$1
subscriptionId=$2
location=$3
currentDir=$4
# gitrepo=$5
# branch=$6

if [[ -z "$prefix" || -z "$subscriptionId" || -z "$location" || -z "$currentDir" ]]
then
    echo "Required parameters not provided. Exiting setup!"
    exit 1
else
    echo "Starting setup!"
fi

scriptsPath="$currentDir/Utils/scripts"
## full path for the scripts
echo $scriptsPath 

## az login
echo "az login and set account"
az login ## --identity ##--username <client_id|object_id|resource_id>

azlogin=$(az account show)

if [ -z "$azlogin" ];
then
echo "az login unsuccsessful. Exiting setup!"
exit 1
fi

az account set -s $subscriptionId

az config set extension.use_dynamic_install=yes_without_prompt

# Move to the directory that contains the .csproj file
cd $currentDir/SchedulePipelineFunctionApp

# Build the project 
dotnet build --configuration Release
# Publish the project into a directory of your choice. I chose /bin/publish
dotnet publish --configuration Release --output ./bin/publish
# Move to the directory with the publish profile
cd bin/publish/
# Zip the publish files
zip -r $currentDir/SchedulePipelineFunctionApp.zip *

# Back out of the publish directory
cd  $currentDir/AdxIngestFunctionApp
# Build the project 
dotnet build --configuration Release
# Publish the project into a directory of your choice. I chose /bin/publish
dotnet publish --configuration Release --output ./bin/publish
# Move to the directory with the publish profile
cd bin/publish/
# Zip the publish files
zip -r $currentDir/AdxIngestFunctionApp.zip *

## Create resource group
echo "Creating resource group"
rg=$prefix-RG
az group create --location $location --name $rg ##--tags "createdBwy=$()"

## Create managed identity and update keyvault
## check permissions to create msi
echo "Creating managed identity"
msi=$(az identity create -g $rg -n $prefix-msi | jq -r .id)
msi=${msi/resourcegroups/resourceGroups}
echo $msi

msiprincipalId=$(az identity show --ids $msi --query principalId --out tsv)
echo $msiprincipalId

msiclientId=$(az identity show --ids $msi --query clientId --out tsv)
echo $msiclientId

## Create Storage account
echo "Creating Storage account"
stor="$prefix"stor
rawDataContainerName="data"

az storage account create --name $stor --resource-group $rg --location $location --sku Standard_LRS

az role assignment create \
    --assignee "$msiprincipalId" \
    --role "contributor"  \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$stor

key=$(az storage account keys list -g $rg -n $stor --query [0].value -o tsv)
echo "SAS for Storage Account"
endDate=`date -u -d "1 year" '+%Y-%m-%dT%H:%MZ'`
sas=$(az storage account generate-sas --permissions acdrw --account-name $stor --account-key $key --https-only --services bfqt --resource-types sco --expiry $endDate -o tsv)     
sas="?$sas"
                
az storage container create --name $rawDataContainerName --account-name $stor --sas-token $sas 

az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee "$msiprincipalId" \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$stor

## create container to upload table script
az storage container create --name scripts --account-name $stor --sas-token $sas 

## ADD Permissions
## upload kql scripts to storage account
az storage blob upload --account-name $stor --container-name scripts \
  --name table_scripts.kql --file $scriptsPath/table_scripts.kql \
  --sas-token $sas --overwrite

## TODO: set purge policy
## az storage account management-policy create --account-name $stor --policy @policy.json --resource-group $rg

## Create ADX
echo "Creating Adx and database"
az extension add -n kusto

## https://learn.microsoft.com/en-us/azure/data-explorer/manage-cluster-choose-sku
az kusto cluster create --cluster-name $prefix-adx --sku name="Dev(No SLA)_Standard_E2a_v4" tier="Basic" --resource-group $rg --location $location

az role assignment create \
    --assignee "$msiprincipalId" \
    --role "contributor"  \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Kusto/Clusters/$prefix-adx

## create db
metricsdbName=$prefix-metricsdb

az kusto database create --cluster-name $prefix-adx \
  --database-name $metricsdbName --resource-group $rg \
  --read-write-database soft-delete-period=P365D hot-cache-period=P31D location=$location

az role assignment create \
    --assignee "$msiprincipalId" \
    --role "contributor"  \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Kusto/Clusters/$prefix-adx/Databases/$metricsdbName

## set adx connection string to keyvault
adxConnectionString=$(az kusto cluster show --cluster-name $prefix-adx --resource-group $rg -o tsv --query "uri")
adxIngestionString=$(az kusto cluster show --cluster-name $prefix-adx --resource-group $rg -o tsv --query "dataIngestionUri")

## Create tables
az kusto script create --cluster-name $prefix-adx --database-name $metricsdbName \
--name table_scripts --resource-group $rg --script-url "https://$stor.blob.core.windows.net/scripts/table_scripts.kql" --script-url-sas-token "$sas"

blobConnectionString=$(az storage account show-connection-string --name $stor --resource-group $rg --subscription $subscriptionId -o tsv)

## create service bus queue
echo "Creating Servicebus"
sbQueueName=$prefix-metricsq

az servicebus namespace create --resource-group $rg --name $prefix-sbns --location $location
az servicebus queue create --resource-group $rg --namespace-name $prefix-sbns --name $sbQueueName

## get service bus connection string and queue name
sbConnStr=$(az servicebus namespace authorization-rule keys list --resource-group $rg \
--namespace-name $prefix-sbns --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)  

## Deploy functions
echo "Deploying functions"
functionsVersion="4"

az functionapp create --name TimerStartPipelineFunction-$prefix --storage-account $stor --consumption-plan-location $location  --resource-group $rg --functions-version $functionsVersion
## az functionapp deployment source config --branch $branch --manual-integration --name TimerStartPipelineFunction --repo-url $gitrepo --resource-group $rg
az functionapp deployment source config-zip -g $rg -n TimerStartPipelineFunction-$prefix --src $currentDir/SchedulePipelineFunctionApp.zip
az resource update --resource-group $rg --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-$prefix --set properties.allow=false
az resource update --resource-group $rg --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-$prefix --set properties.allow=false

az functionapp create --name AdxIngestFunction-$prefix --storage-account $stor --consumption-plan-location $location --resource-group $rg --functions-version $functionsVersion
## az functionapp deployment source config --branch $branch --manual-integration --name AdxIngestFunction --repo-url $gitrepo --resource-group $rg
az functionapp deployment source config-zip -g $rg -n AdxIngestFunction-$prefix --src $currentDir/AdxIngestFunctionApp.zip
az resource update --resource-group $rg --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-$prefix --set properties.allow=false
az resource update --resource-group $rg --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-$prefix --set properties.allow=false

az functionapp identity assign -g $rg -n TimerStartPipelineFunction-$prefix --identities $msi
az functionapp identity assign -g $rg -n AdxIngestFunction-$prefix --identities $msi

az role assignment create \
    --assignee "$msiprincipalId" \
    --role "reader"  \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Web/sites/AdxIngestFunction-$prefix

az role assignment create \
    --assignee "$msiprincipalId" \
    --role "reader"  \
    --scope /subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Web/sites/TimerStartPipelineFunction-$prefix

## Update appsettings
echo "Setup appsettings"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "ServiceBusConnection=$sbConnStr"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "adxConnectionString=$adxConnectionString"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "metricsdbName=$metricsdbName"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "adxIngestionURI=$adxIngestionString"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "queueName=$sbQueueName"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "rawDataContainerName=$rawDataContainerName"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "storageAccountName=$stor"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "msiclientId=$msiclientId"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "storagesas=$sas"
az functionapp config appsettings set --name AdxIngestFunction-$prefix --resource-group $rg --settings "blobConnectionString=$blobConnectionString"


az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "ServiceBusConnection=$sbConnStr"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "adxConnectionString=$adxConnectionString"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "metricsdbName=$metricsdbName"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "adxIngestionURI=$adxIngestionString"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "queueName=$sbQueueName"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "rawDataContainerName=$rawDataContainerName"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "storageAccountName=$stor"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "msiclientId=$msiclientId"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "storagesas=$sas"
az functionapp config appsettings set --name TimerStartPipelineFunction-$prefix --resource-group $rg --settings "blobConnectionString=$blobConnectionString"


## tenantId=$(az account show -o tsv --query "homeTenantId")
## Check if we have to add scopes?  
METRICS_FOLDER_PATH=$scriptsPath/dashboard_templates

echo "Create SP for grafana"
aadSP=$(az ad sp create-for-rbac -n $prefix-sp --role contributor --scopes /subscriptions/$subscriptionId/resourceGroups/$rg) 
sleep 30

echo $aadSP

tenantId=$(echo "$aadSP" | jq -r .tenant)
clientId=$(echo "$aadSP" | jq -r .appId)
clientSecret=$(echo "$aadSP" | jq -r .password)

echo "Add permissions for grafana to access adx and db"
az kusto cluster-principal-assignment create --cluster-name "$prefix-adx" --principal-id "$clientId" \
 --principal-type "App" --role "AllDatabasesAdmin" --tenant-id "$tenantId" \
 --principal-assignment-name "$prefix-kusto-sp" --resource-group "$rg"

az kusto database-principal-assignment create --cluster-name "$prefix-adx" \
 --database-name "$metricsdbName" --principal-id "$clientId" --principal-type "App" \
 --role "Admin" --tenant-id "$tenantId" --principal-assignment-name "$prefix-kusto-sp" --resource-group "$rg"

az kusto cluster-principal-assignment  create --cluster-name "$prefix-adx" --principal-id "$msiprincipalId" \
 --principal-type "App" --role "AllDatabasesAdmin" --tenant-id "$tenantId" \
 --principal-assignment-name "$prefix-kusto-msi" --resource-group "$rg"

az kusto database-principal-assignment create --cluster-name "$prefix-adx" --database-name "$metricsdbName" \
 --principal-id "$msiprincipalId" --principal-type "App" --role "Admin" --tenant-id "$tenantId" \
 --principal-assignment-name "$prefix-db-msi" --resource-group "$rg"

sleep 5

echo "Create azure managed grafana instance"
echo "Configure dashboard"
cd $scriptsPath
/bin/bash ./setup-grafana.sh "$prefix" "$location" "$tenantId" "$subscriptionId" "$clientId" "$clientSecret" "$adxConnectionString" "$metricsdbName" "$METRICS_FOLDER_PATH"
