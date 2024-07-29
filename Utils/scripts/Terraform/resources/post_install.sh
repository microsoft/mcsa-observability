#!/bin/bash

# Retrieve the outputs and export them as environment variables
export spDisplayName=$(terraform output -raw sp_display_name)
export resourceGroupName=$(terraform output -raw resource_group_name)
export appName=$(terraform output -raw app_name)
export storageAccountId=$(terraform output -raw storage_account_id)  # Ensure this output is defined in main.tf

# Step 1: Retrieve the Service Principal Object ID
spObjectId=$(az ad sp list --display-name "$spDisplayName" --query "[0].id" --output tsv)

# Ensure the SP Object ID was retrieved
if [ -z "$spObjectId" ]; then
  echo "Failed to retrieve Service Principal Object ID."
  exit 1
fi

# Step 2: Set the App Setting in the Function App
az functionapp config appsettings set --name "$appName" --resource-group "$resourceGroupName" --settings "kustoMSIObjectId=$spObjectId"

# Ensure the app setting was updated
if [ $? -ne 0 ]; then
  echo "Failed to update app setting 'kustoMSIObjectId'."
  exit 1
fi

echo "App setting 'kustoMSIObjectId' updated successfully."

# Step 3: Assign the Storage Blob Data Contributor role to the Service Principal
az role assignment create --assignee "$spObjectId" --role "Storage Blob Data Contributor" --scope "$storageAccountId"

# Ensure the role assignment was successful
if [ $? -ne 0 ]; then
  echo "Failed to assign role 'Storage Blob Data Contributor' to the Service Principal."
  exit 1
fi

echo "Role 'Storage Blob Data Contributor' assigned successfully to the Service Principal."

export TF_VAR_database_name=$(terraform output -raw database_name)
export TF_VAR_cluster_url=$(terraform output -raw cluster_url)
export TF_VAR_sp_object_id=$(terraform output -raw sp_object_id)
export TF_VAR_prefix=$(terraform output -raw prefix)
export TF_VAR_url=$(az grafana show -g $TF_VAR_prefix-RG -n $TF_VAR_prefix-grafana -o json | jq -r .properties.endpoint)
export TF_VAR_token=$(az grafana api-key create --key `date +%s` --name $TF_VAR_prefix-grafana -g $TF_VAR_prefix-RG -r editor --time-to-live 60m -o json | jq -r .key)