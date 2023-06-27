#!/bin/bash

prefix=$1
METRICS_FOLDER_PATH=$2
## update drill down links
echo "Update drill down links"
endpoint=$(az grafana show --name $prefix-grafana --resource-group $prefix-RG -o tsv --query properties.endpoint)
echo $endpoint
queryparams="?orgId=1\${__url_time_range}&var-selecteddate=\${__data.fields.date}&\${Region:queryparam}&\${Subscriptions:queryparam}&\${Solution:queryparam}"

storageuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG  --query "[?contains(@.title, 'Storage')].uid | [1]" -o tsv)
storagedrilldown=$endpoint/d/$storageuid/storage$queryparams
echo $storagedrilldown


keyvaultuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Keyvault')].uid" -o tsv)
keyvaultdrilldown=$endpoint/d/$keyvaultuid/keyvault$queryparams
echo $keyvaultdrilldown

aksuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'AksServerNode')].uid" -o tsv)
aksdrilldown=$endpoint/d/$aksuid/aksservernode$queryparams
echo $aksdrilldown

firewalluid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Firewalls')].uid" -o tsv)
firewalldrilldown=$endpoint/d/$firewalluid/firewalls$queryparams
echo $firewalldrilldown

lbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Loadbalancer')].uid" -o tsv)
lbdrilldown=$endpoint/d/$lbuid/loadbalancer$queryparams
echo $lbdrilldown

cosmosdbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'CosmosDB')].uid" -o tsv)
cosmosdbdrilldown=$endpoint/d/$cosmosdbuid/cosmosdb-details$queryparams
echo $cosmosdbdrilldown

cognitiveservicebuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'CognitiveServices')].uid" -o tsv)
cognitiveservicedrilldown=$endpoint/d/$cognitiveservicebuid/cognitiveservices$queryparams
echo $cognitiveservicedrilldown

containerregistrybuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'ContainerRegistry')].uid" -o tsv)
containerregistrydrilldown=$endpoint/d/$containerregistrybuid/containerregistry$queryparams
echo $containerregistrydown

eventshubbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Eventshub')].uid" -o tsv)
eventshubdrilldown=$endpoint/d/$eventshubbuid/eventshub$queryparams
echo $eventshubdrilldown

jsonfile=$METRICS_FOLDER_PATH/AzureResourceObservability-1687853750785.json
echo $jsonfile

echo "$(jq --arg storagedrilldown "$storagedrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="storage drill down details") then .url=$storagedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg keyvaultdrilldown "$keyvaultdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="keyvault drill down details") then .url=$keyvaultdrilldown else . end' $jsonfile)" > $jsonfile
        
echo  "$(jq --arg aksdrilldown "$aksdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="aksservernode drill down details") then .url=$aksdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg firewalldrilldown "$keyvaultdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="firewall drill down details") then .url=$firewalldrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg lbdrilldown "$lbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="loadbalancer drill down details") then .url=$lbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cosmosdbdrilldown "$cosmosdbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="cosmosdb drill down details") then .url=$cosmosdbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cognitiveservicedrilldown "$cognitiveservicedrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="cognitive service drill down details") then .url=$cognitiveservicedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg containerregistrydrilldown "$containerregistrydrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="acr drill down details") then .url=$containerregistrydrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg eventshubdrilldown "$eventshubdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="eventhub drill down details") then .url=$eventshubdrilldown else . end' $jsonfile)" > $jsonfile


echo "Managed Grafana: Importing dashboard for $jsonfile file"
az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder Observability_Dashboard --overwrite true --definition @$jsonfile
sleep 2