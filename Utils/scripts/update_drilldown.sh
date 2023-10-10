#!/bin/bash

prefix=$1
METRICS_FOLDER_PATH=$2
## update drill down links
echo "Update drill down links"
endpoint=$(az grafana show --name $prefix-grafana --resource-group $prefix-RG -o tsv --query properties.endpoint)
echo $endpoint
queryparams="?orgId=1\${__url_time_range}&var-selecteddate=\${__data.fields.date}&\${Region:queryparam}&\${Subscriptions:queryparam}&\${Solution:queryparam}"
queryparams_usage="?orgId=1\${__url_time_range}&var-selecteddate=\${__data.fields.date}&\${Region:queryparam}&\${Subscriptions:queryparam}&\${Solution:queryparam}&\${Model:queryparam}"

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

eventhubsbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Eventhubs')].uid" -o tsv)
eventhubsdrilldown=$endpoint/d/$eventhubsbuid/eventhubs$queryparams
echo $eventhubsdrilldown

loganalyticsbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'LogAnalytics')].uid" -o tsv)
loganalyticsdrilldown=$endpoint/d/$loganalyticsbuid/loganalytics$queryparams
echo $loganalyticsdrilldown

deploymentcount1uid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'DeploymentCount-1')].uid" -o tsv)
deploymentcount1drilldown=$endpoint/d/$deploymentcount1uid/deploymentcount-1$queryparams
echo $deploymentcount1drilldown

latencybyregion1uid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'LatencyByRegion-1')].uid" -o tsv)
latencybyregion1drilldown=$endpoint/d/$latencybyregion1uid/latencybyregion-1$queryparams
echo $latencybyregion1drilldown

latencybyregion2uid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'LatencyByRegion-2')].uid" -o tsv)
deploymentcount2drilldown=$endpoint/d/$latencybyregion2uid/latencybyregion-2$queryparams
echo $latencybyregion2drilldown

tokencount1uid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'TokenCount-1')].uid" -o tsv)
tokencount1drilldown=$endpoint/d/$tokencount1uid/tokencount-1$queryparams
echo $tokencount1drilldown

tokencount2uid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'TokenCount-2')].uid" -o tsv)
tokencount2drilldown=$endpoint/d/$tokencount2uid/tokencount-2$queryparams
echo $tokencount2drilldown

jsonfile=$METRICS_FOLDER_PATH/AzureResourceObservability-1687853750785.json
echo $jsonfile

echo "$(jq --arg storagedrilldown "$storagedrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="storage drill down details") then .url=$storagedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg keyvaultdrilldown "$keyvaultdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="keyvault drill down details") then .url=$keyvaultdrilldown else . end' $jsonfile)" > $jsonfile
        
echo  "$(jq --arg aksdrilldown "$aksdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="aksservernode drill down details") then .url=$aksdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg firewalldrilldown "$firewalldrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="firewall drill down details") then .url=$firewalldrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg lbdrilldown "$lbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="loadbalancer drill down details") then .url=$lbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cosmosdbdrilldown "$cosmosdbdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="cosmosdb drill down details") then .url=$cosmosdbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cognitiveservicedrilldown "$cognitiveservicedrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="cognitive service drill down details") then .url=$cognitiveservicedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg containerregistrydrilldown "$containerregistrydrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="acr drill down details") then .url=$containerregistrydrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg eventhubsdrilldown "$eventhubsdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="eventhubs drill down details") then .url=$eventhubsdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg loganalyticsdrilldown "$loganalyticsdrilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="loganalytics drill down details") then .url=$loganalyticsdrilldown else . end' $jsonfile)" > $jsonfile

jsonfile_usage=$METRICS_FOLDER_PATH/AzureResourceUsage.json
echo $jsonfile_usage

echo "$(jq --arg deploymentcount1drilldown "$deploymentcount1drilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="Model Deployment by Region - drilldown details") then .url=$deploymentcount1drilldown else . end' $jsonfile_usage)" > $jsonfile_usage
echo "$(jq --arg latencybyregion1drilldown "$latencybyregion1drilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="Latency by Region - drilldown details") then .url=$latencybyregion1drilldown else . end' $jsonfile_usage)" > $jsonfile_usage
echo "$(jq --arg latencybyregion2drilldown "$latencybyregion2drilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="Latency by Model - drilldown details") then .url=$latencybyregion2drilldown else . end' $jsonfile_usage)" > $jsonfile_usage
echo "$(jq --arg tokencount1drilldown "$tokencount1drilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="Token Usage by Model - drilldown details") then .url=$tokencount1drilldown else . end' $jsonfile_usage)" > $jsonfile_usage
echo "$(jq --arg tokencount2drilldown "$tokencount2drilldown" '.panels[].fieldConfig.defaults.links[]? |= if(.title=="Token Usage by Region - drilldown details") then .url=$tokencount2drilldown else . end' $jsonfile_usage)" > $jsonfile_usage


echo "Managed Grafana: Importing dashboard for $jsonfile file"
az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder Observability_Dashboard --overwrite true --definition @$jsonfile
sleep 2
echo "Managed Grafana: Importing dashboard for $jsonfile_usage file"
az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder Usage_Dashboard --overwrite true --definition @$jsonfile_usage
sleep 2