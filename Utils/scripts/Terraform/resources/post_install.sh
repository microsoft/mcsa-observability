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