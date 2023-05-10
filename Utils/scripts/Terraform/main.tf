# Configure the Azure provider
terraform {
  required_version = ">= 1.1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.52.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
        prevent_deletion_if_contains_resources = false
   }
  }
  subscription_id = "${var.subscriptionId}"
}

#access the configuration of the AzureRM provider - current user credentials
data "azurerm_client_config" "current" {}
data azuread_client_config "current" {}
data "azurerm_subscription" "primary" {
}
output "client_id" {
  value = "${data.azurerm_client_config.current.client_id}"
}
output "tenant_id" {
  value = "${data.azurerm_client_config.current.tenant_id}"
}
output "subscription_id" {
  value = "${data.azurerm_client_config.current.subscription_id}"
}
output "object_id" {
  value = "${data.azurerm_client_config.current.object_id}"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-RG"
  location = "${var.location}"
}

#create a user managed identity
resource "azurerm_user_assigned_identity" "terraform" {
  location            = azurerm_resource_group.rg.location
  name                = "${var.prefix}-msi"
  resource_group_name = azurerm_resource_group.rg.name
}

output "terraform_identity_object_id" {
  value = azurerm_user_assigned_identity.terraform.principal_id
}

resource "time_sleep" "wait_managed_identity_creation" {
  depends_on = [azurerm_user_assigned_identity.terraform]

  create_duration = "60s"
}

#create a storage account
resource "azurerm_storage_account" "this" {
  name                     = "${var.prefix}stor"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  depends_on = [time_sleep.wait_managed_identity_creation]

  tags = {
    environment = "development"
  }
}

resource "time_sleep" "wait_storage_account_creation" {
  depends_on = [azurerm_user_assigned_identity.terraform]

  create_duration = "180s"
}

#create storage containers
resource "azurerm_storage_container" "data" {
  name 			= "data"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
  depends_on = [time_sleep.wait_storage_account_creation]
  
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
  depends_on = [time_sleep.wait_storage_account_creation]
}

resource "time_sleep" "wait_storage_container_creation" {
  depends_on = [azurerm_storage_container.scripts]

  create_duration = "5s"
}

locals{
    today=formatdate("YYYY-MM-DD", timestamp())
    next_year=formatdate("YYYY-MM-DD", timeadd(timestamp(), "8640h"))
}

#create sas tokens for azure blob
data "azurerm_storage_account_blob_container_sas" "this" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  container_name    = azurerm_storage_container.scripts.name
  https_only        = true
  depends_on = [time_sleep.wait_storage_container_creation]

  start  = local.today
  expiry = local.next_year

  permissions {
    read   = true
    add    = true
    create = true
    write  = true
    delete = true
    list   = true
  }
}

output "sas_url_query_string_container" {
  value = data.azurerm_storage_account_blob_container_sas.this.sas
sensitive = true
}

#create blob to store the kql query
resource "azurerm_storage_blob" "this" {
  name                   = "table_scripts.kql"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.cwd}/../table_scripts.kql"
  depends_on = [time_sleep.wait_storage_container_creation]
}

resource "time_sleep" "wait_storage_blob_creation" {
  depends_on = [azurerm_storage_blob.this]

  create_duration = "5s"
}

#create a kusto cluster
resource "azurerm_kusto_cluster" "this" {
  name                = "${var.prefix}adx"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name     = "Standard_D13_v2"
    capacity = 2
  }

  identity {
    type = "UserAssigned"
    identity_ids = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.prefix}-RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.prefix}-msi"]
  }

  depends_on = [time_sleep.wait_storage_blob_creation]

  tags = {
    Environment = "Development"
  }
}

resource "time_sleep" "wait_kusto_cluster_creation" {
  depends_on = [azurerm_kusto_cluster.this]

  create_duration = "60s"
}

resource "azurerm_kusto_database" "database" {
  name                = "${var.prefix}-metricsdb"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  cluster_name        = azurerm_kusto_cluster.this.name
  depends_on = [time_sleep.wait_kusto_cluster_creation]

  hot_cache_period   = "P7D"
  soft_delete_period = "P31D"
}

resource "time_sleep" "wait_kusto_database_creation" {
  depends_on = [azurerm_kusto_database.database]

  create_duration = "10s"
}

resource "azurerm_kusto_script" "table" {
  name                               = "metricsdbtables"
  database_id                        = azurerm_kusto_database.database.id
  url                                = azurerm_storage_blob.this.id
  sas_token                          = data.azurerm_storage_account_blob_container_sas.this.sas
  continue_on_errors_enabled         = true
  force_an_update_when_value_changed = "first"
  depends_on = [time_sleep.wait_kusto_database_creation]
}

resource "time_sleep" "wait_kusto_table_creation" {
  depends_on = [azurerm_kusto_script.table]

  create_duration = "4s"
}

#create service bus 
resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.prefix}-sbns"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  depends_on = [time_sleep.wait_kusto_table_creation]

  tags = {
    source = "terraform"
  }
}
#create a service bus namespace 
resource "azurerm_servicebus_queue" "this" {
  name         = "${var.prefix}-sbq"
  namespace_id = azurerm_servicebus_namespace.this.id

  enable_partitioning = true
}

resource "time_sleep" "wait_servicebus_creation" {
  depends_on = [azurerm_servicebus_queue.this]

  create_duration = "10s"
}

locals {
    metricdb_name = "${var.prefix}-metricsdb"
    queue_name = "${var.prefix}-sbq"
    storage_account_name = "${var.prefix}stor"

}

#create function apps
resource "azurerm_service_plan" "timerstartpipelineapp" {
  name                = "timerstartpipelineapp-service-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "Y1"
  depends_on = [time_sleep.wait_servicebus_creation]
}

resource "azurerm_application_insights" "timerstartpipelineapp" {
  name                = "TimerStartPipelineFunction-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  depends_on = [time_sleep.wait_servicebus_creation]
}

resource "azurerm_windows_function_app" "timerstartpipelineapp" {
  name                = "TimerStartPipelineFunction-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.timerstartpipelineapp.id
  depends_on = [time_sleep.wait_servicebus_creation]

  identity {
    type = "UserAssigned"
    identity_ids = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.prefix}-RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.prefix}-msi"]
  }

  site_config {}

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY=azurerm_application_insights.timerstartpipelineapp.instrumentation_key
	ServiceBusConnection=azurerm_servicebus_namespace.this.default_primary_connection_string
    adxConnectionString=azurerm_kusto_cluster.this.uri
    metricsdbName=local.metricdb_name
    adxIngestionURI=azurerm_kusto_cluster.this.data_ingestion_uri
    queueName=local.queue_name
    rawDataContainerName=azurerm_storage_container.data.name
    storageAccountName=local.storage_account_name
    msiclientId=azurerm_user_assigned_identity.terraform.client_id
    storagesas=data.azurerm_storage_account_blob_container_sas.this.sas
    blobConnectionString=azurerm_storage_account.this.primary_connection_string
	}
}

locals {
    dotnet_build_timerpipelineapp         = "dotnet build ${path.cwd}/../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.csproj -c Release"
    dotnet_publish_timerpipelineapp       = "dotnet publish ${path.cwd}/../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.csproj -o ${path.cwd}/../../../SchedulePipelineFunctionApp/bin/publish"
    disable_basic_auth_timerpipelineapp_scm   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-${var.prefix} --set properties.allow=false"
    disable_basic_auth_timerpipelineapp_ftp   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-${var.prefix} --set properties.allow=false"
}

resource "time_sleep" "wait_timelinestartpipeline_creation" {
  depends_on = [azurerm_windows_function_app.timerstartpipelineapp]
  create_duration = "10s"
}
resource "null_resource" "dotnet_build_timerpipelineapp" {
  provisioner "local-exec" {
    command = local.dotnet_build_timerpipelineapp
  }
  depends_on = [time_sleep.wait_timelinestartpipeline_creation]
  triggers = {
    dotnet_build_command = local.dotnet_build_timerpipelineapp
  }
}

resource "null_resource" "dotnet_publish_timerpipelineapp" {
  provisioner "local-exec" {
    command = local.dotnet_publish_timerpipelineapp
  }
  depends_on = [null_resource.dotnet_build_timerpipelineapp]
  triggers = {
    dotnet_build_command = local.dotnet_publish_timerpipelineapp
  }
}

resource "time_sleep" "wait_dotnet_publish_timerpipelineapp" {
  depends_on = [null_resource.dotnet_publish_timerpipelineapp]
  create_duration = "10s"
}

data "archive_file" "file_function_app_timerpipeline" {
  type        = "zip"
  source_dir  = "${path.cwd}/../../../SchedulePipelineFunctionApp/bin/publish"
  output_path = "${path.cwd}/../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.zip"
  depends_on = [time_sleep.wait_dotnet_publish_timerpipelineapp]
}

output "full-file_path" {
value = data.archive_file.file_function_app_timerpipeline.output_path
}
locals {
    publish_code_command_timerpipeline = "az functionapp deployment source config-zip -g ${var.prefix}-RG -n TimerStartPipelineFunction-${var.prefix} --src ${path.cwd}/../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.zip"
}

resource "time_sleep" "wait_timerpipeline_publish" {
  depends_on = [data.archive_file.file_function_app_timerpipeline]

  create_duration = "60s"
}

resource "null_resource" "function_app_publish_timerpipeline" {
  provisioner "local-exec" {
    command = local.publish_code_command_timerpipeline
  }
  depends_on = [time_sleep.wait_timerpipeline_publish]
  triggers = {
    publish_code_command = local.publish_code_command_timerpipeline
  }
}

resource "time_sleep" "wait_function_app_publish_timerpipeline" {
  depends_on = [null_resource.function_app_publish_timerpipeline]

  create_duration = "60s"
}


resource "null_resource" "disable_basic_auth_timerpipelineapp_scm" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_timerpipelineapp_scm
  }
  depends_on = [time_sleep.wait_function_app_publish_timerpipeline]
  triggers = {
    disable_basic_auth_timerpipelineapp_scm_command = local.disable_basic_auth_timerpipelineapp_scm
  }
}

resource "null_resource" "disable_basic_auth_timerpipelineapp_ftp" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_timerpipelineapp_ftp
  }
  depends_on = [time_sleep.wait_function_app_publish_timerpipeline]
  triggers = {
    disable_basic_auth_timerpipelineapp_ftp_command = local.disable_basic_auth_timerpipelineapp_ftp
  }
}

resource "azurerm_service_plan" "adxingestionapp" {
  name                = "adxingestionapp-service-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "Y1"
  depends_on = [time_sleep.wait_servicebus_creation]
}

resource "azurerm_application_insights" "adxingestionapp" {
  name                = "AdxIngestFunction-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  depends_on = [time_sleep.wait_servicebus_creation]
}

resource "azurerm_windows_function_app" "adxingestionapp" {
  name                = "AdxIngestFunction-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.adxingestionapp.id
  depends_on = [time_sleep.wait_servicebus_creation]

  identity {
    type = "UserAssigned"
    identity_ids = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.prefix}-RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.prefix}-msi"]
  }

  site_config {
    ftps_state = "Disabled"
  }
  
  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY=azurerm_application_insights.adxingestionapp.instrumentation_key
	ServiceBusConnection=azurerm_servicebus_namespace.this.default_primary_connection_string
    adxConnectionString=azurerm_kusto_cluster.this.uri
    metricsdbName=local.metricdb_name
    adxIngestionURI=azurerm_kusto_cluster.this.data_ingestion_uri
    queueName=local.queue_name
    rawDataContainerName=azurerm_storage_container.data.name
    storageAccountName=local.storage_account_name
    msiclientId=azurerm_user_assigned_identity.terraform.client_id
    storagesas=data.azurerm_storage_account_blob_container_sas.this.sas
    blobConnectionString=azurerm_storage_account.this.primary_connection_string
	}

}

locals {
    dotnet_build_adxingestapp         = "dotnet build ${path.cwd}/../../../AdxIngestFunctionApp/AdxIngestFunctionApp.csproj -c Release"
    dotnet_publish_adxingestapp       = "dotnet publish ${path.cwd}/../../../AdxIngestFunctionApp/AdxIngestFunctionApp.csproj -o ${path.cwd}/../../../AdxIngestFunctionApp/bin/publish"
    disable_basic_auth_adxingestapp_scm   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-${var.prefix} --set properties.allow=false"
    disable_basic_auth_adxingestapp_ftp   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-${var.prefix} --set properties.allow=false"
}

resource "time_sleep" "wait_adxingestionapp_creation" {
  depends_on = [azurerm_windows_function_app.adxingestionapp]
  create_duration = "10s"
}

resource "null_resource" "dotnet_build_adxingestapp" {
  provisioner "local-exec" {
    command = local.dotnet_build_adxingestapp
  }
  depends_on = [time_sleep.wait_adxingestionapp_creation]
  triggers = {
    dotnet_build_command = local.dotnet_build_adxingestapp
  }
}

resource "null_resource" "dotnet_publish_adxingestapp" {
  provisioner "local-exec" {
    command = local.dotnet_publish_adxingestapp
  }
  depends_on = [time_sleep.wait_adxingestionapp_creation]
  triggers = {
    dotnet_build_command = local.dotnet_publish_adxingestapp
  }
}

resource "time_sleep" "wait_dotnet_publish_adxingestapp" {
  depends_on = [null_resource.dotnet_publish_adxingestapp]
  create_duration = "10s"
}

data "archive_file" "file_function_app_adxingest" {
  type        = "zip"
  source_dir  = "${path.cwd}/../../../AdxIngestFunctionApp/bin/publish"
  output_path = "${path.cwd}/../../../AdxIngestFunctionApp/AdxIngestFunctionApp.zip"
  depends_on = [time_sleep.wait_dotnet_publish_adxingestapp]
}

output "full-file_path_adxingestapp" {
value = data.archive_file.file_function_app_adxingest.output_path
}
locals {
    publish_code_command_adxingest = "az functionapp deployment source config-zip -g ${var.prefix}-RG -n AdxIngestFunction-${var.prefix} --src ${path.cwd}/../../../AdxIngestFunctionApp/AdxIngestFunctionApp.zip"
}

resource "time_sleep" "wait_adxingest_publish" {
  depends_on = [data.archive_file.file_function_app_adxingest]

  create_duration = "60s"
}

resource "null_resource" "function_app_publish_adxingest" {
  provisioner "local-exec" {
    command = local.publish_code_command_adxingest
  }
  depends_on = [time_sleep.wait_adxingest_publish]
  triggers = {
    publish_code_command = local.publish_code_command_adxingest
  }
}

resource "time_sleep" "wait_function_app_publish_adxingest" {
  depends_on = [null_resource.function_app_publish_adxingest]

  create_duration = "60s"
}

resource "null_resource" "disable_basic_auth_adxingestapp_scm" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_adxingestapp_scm
  }
  depends_on = [time_sleep.wait_function_app_publish_adxingest]
  triggers = {
    disable_basic_auth_adxingestapp_command = local.disable_basic_auth_adxingestapp_scm
  }
}

resource "null_resource" "disable_basic_auth_adxingestapp_ftp" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_adxingestapp_ftp
  }
  depends_on = [time_sleep.wait_function_app_publish_adxingest]
  triggers = {
    disable_basic_auth_adxingestapp_ftp_command = local.disable_basic_auth_adxingestapp_ftp
  }
}


#sleep for 10 seconds to allow function apps to be created
resource "time_sleep" "wait_function_app_creation" {
  depends_on = [azurerm_windows_function_app.timerstartpipelineapp, azurerm_windows_function_app.adxingestionapp]

  create_duration = "10s"
}

locals {
    dashboard_templates = "${path.cwd}/../dashboard_templates"
    set_exec_permissions = "chmod 755 ${path.cwd}/../setup-grafana.sh"
    run_setup_grafana = "${path.cwd}/../setup-grafana.sh ${var.prefix} ${var.location} ${data.azurerm_client_config.current.subscription_id} ${azurerm_kusto_cluster.this.uri} ${local.metricdb_name} ${local.dashboard_templates} ${azurerm_resource_group.rg.name} ${azurerm_user_assigned_identity.terraform.principal_id}"
}

resource "time_sleep" "wait_setup_grafana" {
  depends_on = [null_resource.function_app_publish_adxingest]

  create_duration = "60s"
}
resource "null_resource" "set_exec_permissions" {
  provisioner "local-exec" {
    command = local.set_exec_permissions
  }
  depends_on = [time_sleep.wait_setup_grafana]
  triggers = {
    exec_permissions = local.set_exec_permissions
  }
}
resource "time_sleep" "wait_set_exec_permissions" {
  depends_on = [null_resource.function_app_publish_adxingest]

  create_duration = "30s"
}

resource "null_resource" "setup_grafana" {
  provisioner "local-exec" {
    command = local.run_setup_grafana
  }
  depends_on = [time_sleep.wait_set_exec_permissions]
  triggers = {
    publish_code_command = local.run_setup_grafana
  }
}

#add permissions
resource "azurerm_role_assignment" "adx" {
  scope                = azurerm_kusto_cluster.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id#data.azurerm_client_config.current.object_id
  depends_on = [time_sleep.wait_setup_grafana]
}

resource "azurerm_role_assignment" "storage" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}

resource "azurerm_role_assignment" "database" {
  scope                = azurerm_kusto_database.database.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}

#add storage_blob_data_contributor to the storage account
resource "azurerm_role_assignment" "msi_storage_role" {
  scope                = azurerm_storage_account.this.id#data.azurerm_subscription.primary.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}

#add reader to the timerstartpipelineapp
resource "azurerm_role_assignment" "msi_timerstartpipelineapp_role" {
  scope                = azurerm_windows_function_app.timerstartpipelineapp.id#data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}

#add reader to the adxingestapp
resource "azurerm_role_assignment" "msi_adxingestionapp_role" {
  scope                = azurerm_windows_function_app.adxingestionapp.id#data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}

# add monitoring reader access to msi
resource "azurerm_role_assignment" "msi_monitoringreader_role" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [time_sleep.wait_setup_grafana]
}
