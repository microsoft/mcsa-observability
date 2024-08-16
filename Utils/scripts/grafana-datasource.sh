#!/bin/bash

prefix=$1
cluster_Url=$2
dbName=$3
METRICS_FOLDER_PATH=$4

echo $prefix
echo $cluster_Url
echo $dbName
echo $METRICS_FOLDER_PATH

az config set extension.use_dynamic_install=yes_without_prompt

echo "Managed Grafana: Creating Data Explorer Datasource"
az grafana data-source create -n $prefix-grafana --definition '{
  "name": "Observability Metrics Data Source",
  "type": "grafana-azure-data-explorer-datasource",
  "typeLogoUrl": "public/plugins/grafana-azure-data-explorer-datasource/img/logo.png",
  "access": "proxy",
  "url": "api/datasources/proxy/2",
  "password": "",
  "user": "",
  "database": "",
  "basicAuth": false,
  "isDefault": false,
  "jsonData": {
    "clusterUrl": "'"$cluster_Url"'",
    "dataConsistency": "strongconsistency",
    "defaultDatabase": "'"$dbName"'",
    "defaultEditorMode": "visual",
    "schemaMappings": [],
    "azureCredentials": {
      "authType": "msi"
    }
  },
  "readOnly": false
}'

echo "Managed Grafana: Grab the UID of the Azure Data Explorer data source..."
response=$(az grafana data-source show --data-source "Observability Metrics Data Source" --name $prefix-grafana)
uid=$( jq -r  '.uid' <<< "$response" )
echo $uid

echo $METRICS_FOLDER_PATH
# Populates the dashboards with the data source UID
function populate_datasource_uid() {
  FILE_LIST="$METRICS_FOLDER_PATH/*"
  for file in $FILE_LIST 
    do
        echo "Managed Grafana: Updating datasource uid for $file file"
        echo "$( jq --arg uid "$uid" '.panels[].datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        echo "$( jq --arg uid "$uid" '.panels[].targets[]?.datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        echo "$( jq --arg dbName "$dbName" '.panels[].targets[]?.database = $dbName' $file)" > $file
        echo "$( jq --arg uid "$uid" '.templating.list[].datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        sleep 2
    done
}

populate_datasource_uid $uid $METRICS_FOLDER_PATH