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

jsonfile=$METRICS_FOLDER_PATH/Azure Resource Observability-1687853750785.json
echo $jsonfile

echo "$(jq --arg storagedrilldown "$storagedrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="storage drill down details") then .url=$storagedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg keyvaultdrilldown "$keyvaultdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="keyvault drill down details") then .url=$keyvaultdrilldown else . end' $jsonfile)" > $jsonfile
        
echo  "$(jq --arg aksdrilldown "$aksdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="aksservernode drill down details") then .url=$aksdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg firewalldrilldown "$keyvaultdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="firewall drill down details") then .url=$firewalldrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg lbdrilldown "$lbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="loadbalancer drill down details") then .url=$lbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cosmosdbdrilldown "$cosmosdbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="cosmosdb drill down details") then .url=$cosmosdbdrilldown else . end' $jsonfile)" > $jsonfile


echo "Managed Grafana: Importing dashboard for $jsonfile file"
az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder Observability_Dashboard --overwrite true --definition @$jsonfile
sleep 2