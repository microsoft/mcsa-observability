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
    azapi = {
      source = "azure/azapi"
    }
    grafana = {
      source = "grafana/grafana"
      version = "1.36.1"
    }
    zipper = {
      source = "ArthurHlt/zipper"
      version = "0.14.0"
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

provider "azapi" {
}

provider "zipper" {
  skip_ssl_validation = false
}

#access the configuration of the AzureRM provider - current user credentials
data "azurerm_client_config" "current" {}
data "azuread_user" "current_user" {
  object_id = data.azurerm_client_config.current.object_id
}
data azuread_client_config "current" {}
data "azurerm_subscription" "primary" {
}


locals{
    startdate_formatted=formatdate("YYYY-MM-DD", timeadd(timestamp(), "-72h"))
    expirydate_formatted=formatdate("YYYY-MM-DD", timeadd(timestamp(), "8568h"))
    startdate=timeadd(timestamp(), "-72h")
    expirydate=timeadd(timestamp(), "8568h")
    metricdb_name = "${var.prefix}-metricsdb"
    serviceBusMSIString="Endpoint=sb://${azurerm_servicebus_namespace.this.name}.servicebus.windows.net/;Authentication=ManagedIdentity"
    queue_name = "${var.prefix}-sbq"
    storage_account_name = "${var.prefix}stor"
    dotnet_build_timerpipelineapp         = "dotnet build ${path.cwd}/../../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.csproj -c Release"
    dotnet_publish_timerpipelineapp       = "dotnet publish ${path.cwd}/../../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.csproj -o ${path.cwd}/../../../../SchedulePipelineFunctionApp/bin/publish"
    source_zip_path_app1                  = "${path.cwd}/../../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.zip"
    generate_access_token_app1                 = "$(az account get-access-token --query \"accessToken\" --output tsv)"
    destination_zip_path_app1             = "https://TimerStartPipelineFunction-${var.prefix}.scm.azurewebsites.net/api/zipdeploy"
    curl_zip_deploy_app1                       = "curl -X POST --data-binary @\"${local.source_zip_path_app1}\" -H \"Authorization: Bearer ${local.generate_access_token_app1}\" \"${local.destination_zip_path_app1}\""
    disable_basic_auth_timerpipelineapp_scm   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-${var.prefix} --set properties.allow=false"
    disable_basic_auth_timerpipelineapp_ftp   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/TimerStartPipelineFunction-${var.prefix} --set properties.allow=false"
    dotnet_build_adxingestapp         = "dotnet build ${path.cwd}/../../../../AdxIngestFunctionApp/AdxIngestFunctionApp.csproj -c Release"
    dotnet_publish_adxingestapp       = "dotnet publish ${path.cwd}/../../../../AdxIngestFunctionApp/AdxIngestFunctionApp.csproj -o ${path.cwd}/../../../../AdxIngestFunctionApp/bin/publish"
    source_zip_path_app2                  = "${path.cwd}/../../../../AdxIngestFunctionApp/AdxIngestFunctionApp.zip"
    generate_access_token_app2                 = "$(az account get-access-token --query \"accessToken\" --output tsv)"
    destination_zip_path_app2             = "https://AdxIngestFunction-${var.prefix}.scm.azurewebsites.net/api/zipdeploy"
    curl_zip_deploy_app2                       = "curl -X POST --data-binary @\"${local.source_zip_path_app2}\" -H \"Authorization: Bearer ${local.generate_access_token_app2}\" \"${local.destination_zip_path_app2}\""
    disable_basic_auth_adxingestapp_scm   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-${var.prefix} --set properties.allow=false"
    disable_basic_auth_adxingestapp_ftp   = "az resource update --resource-group ${azurerm_resource_group.rg.name} --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/AdxIngestFunction-${var.prefix} --set properties.allow=false"
    dashboard_templates = "${path.cwd}/../../dashboard_templates"
    #set_exec_permissions = "chmod 755 ${path.cwd}/../../setup-grafana-terraform.sh"
    #run_setup_grafana = "${path.cwd}/../../setup-grafana-terraform.sh ${var.prefix} ${var.location} ${data.azurerm_client_config.current.subscription_id} ${azurerm_kusto_cluster.this.uri} ${local.metricdb_name} ${local.dashboard_templates} ${azurerm_resource_group.rg.name} ${azurerm_user_assigned_identity.terraform.principal_id}"
}

resource "null_resource" "always_run" {
  triggers = {
    timestamp = "${timestamp()}"
  }
}

#create ad application
resource "azuread_application" "this" {
  display_name = "${var.prefix}-sp"
  owners       = [data.azuread_client_config.current.object_id]
}

#create a service principal tagged to ad application
resource "azuread_service_principal" "this" {
  client_id               = azuread_application.this.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

/* #create the secret for the service principal
resource "azuread_service_principal_password" "this" {
  service_principal_id = azuread_service_principal.this.object_id
} */

#create resource group to house resources
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

#create key vault
resource "azurerm_key_vault" "kv" {
  name                        = "${var.prefix}-vault"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  depends_on = [azurerm_resource_group.rg]

  sku_name = "standard"
  
}


/* resource "azurerm_key_vault_secret" "client_secret_secret" {
  name         = "tenant-${data.azurerm_client_config.current.tenant_id}"//azuread_service_principal.this.client_id//"ServicePrincipalClientSecret"
  value        = "{\"ClientId\":\"${azuread_service_principal.this.client_id}\",\"ClientSecret\":\"${azuread_service_principal_password.this.value}\"}"//"${azuread_service_principal.this.client_id}-${azuread_service_principal_password.this.value}"//service_principal_id
  key_vault_id = azurerm_key_vault.kv.id
  depends_on = [azuread_service_principal_password.this]
} */


#create a storage account
resource "azurerm_storage_account" "this" {
  name                     = "${var.prefix}stor"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  shared_access_key_enabled = true
  depends_on = [azurerm_user_assigned_identity.terraform]

  tags = {
    environment = "development"
  }
}

#create storage containers
resource "azurerm_storage_container" "data" {
  name 			= "data"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
  depends_on = [azurerm_storage_account.this]
  
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
  depends_on = [azurerm_storage_account.this]
}

#create sas tokens for storage account
data "azurerm_storage_account_sas" "this" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  https_only        = true
  #signed_version    = "2017-07-29"
  depends_on = [azurerm_storage_account.this]

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = true
    table = true
    file  = true
  }
  start  = local.startdate
  expiry = local.expirydate

  permissions {
    read   = true
    add    = true
    create = true
    write  = true
    delete = true
    list   = true
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

output "sas_url_query_string" {
  value = data.azurerm_storage_account_sas.this.sas
sensitive = true
}

#create blob to store the kql query
resource "azurerm_storage_blob" "this" {
  name                   = "table_scripts.kql"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.cwd}/../../table_scripts.kql"
  depends_on = [azurerm_storage_container.scripts]
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}

# TODO: deployment will succeed but return 'Command is not allowed' error with this resource
# Execute this command manually in ADX to enable ingestion with MSI
/*
resource "azurerm_kusto_script" "ingestionpolicy" {
  name                               = "metricsdbingestionpolicy"
  database_id                        = azurerm_kusto_database.database.id
  continue_on_errors_enabled         = true
  force_an_update_when_value_changed = "first"
  depends_on = [azurerm_kusto_cluster_principal_assignment.user, azurerm_user_assigned_identity.terraform, azurerm_kusto_cluster_principal_assignment.this, azurerm_kusto_cluster_principal_assignment.msi]

  script_content = <<SCRIPT
    .alter-merge cluster policy managed_identity "[{ 'ObjectId' : '${azurerm_kusto_cluster.this.identity.0.principal_id}', 'AllowedUsages' : 'NativeIngestion' }]"
SCRIPT
}
*/

#create a kusto cluster
resource "azurerm_kusto_cluster" "this" {
  name                = "${var.prefix}adx"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name     = "Dev(No SLA)_Standard_E2a_v4"
    capacity = 1
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_storage_account.this, azurerm_resource_group.rg]

  tags = {
    Environment = "Development"
  }
}

#create a database within the kusto cluster
resource "azurerm_kusto_database" "database" {
  name                = "${var.prefix}-metricsdb"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  cluster_name        = azurerm_kusto_cluster.this.name
  depends_on = [azurerm_kusto_cluster.this]

  hot_cache_period   = "P7D"
  soft_delete_period = "P365D"
}


#create tables using the table creation script inside the database
resource "azurerm_kusto_script" "table" {
  name                               = "metricsdbtables"
  database_id                        = azurerm_kusto_database.database.id
  url                                = azurerm_storage_blob.this.id
  sas_token                          = data.azurerm_storage_account_sas.this.sas
  continue_on_errors_enabled         = true
  force_an_update_when_value_changed = "first"
  depends_on = [azurerm_kusto_database.database]
}

#create service bus 
resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.prefix}-sbns"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  depends_on = [azurerm_resource_group.rg]

  tags = {
    source = "terraform"
  }
}
#create a service bus namespace 
resource "azurerm_servicebus_queue" "this" {
  name         = "${var.prefix}-sbq"
  namespace_id = azurerm_servicebus_namespace.this.id
  depends_on = [azurerm_servicebus_namespace.this]
  enable_partitioning = true
}

resource "time_sleep" "wait_servicebus_creation" {
  depends_on = [azurerm_servicebus_queue.this]
  create_duration = "10s"
}

#add key vault access policy to msi
resource "azurerm_key_vault_access_policy" "msiaccess" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.terraform.principal_id #msi
  depends_on = [azurerm_resource_group.rg, azurerm_key_vault.kv]

    secret_permissions = [
      "Get",
      "Set",
      "List"
    ]
}

#add key vault access policy to user
resource "azurerm_key_vault_access_policy" "useraccess" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id #user
  depends_on = [azurerm_resource_group.rg, azurerm_key_vault.kv]

    secret_permissions = [
      "Get",
      "Set",
      "List"
    ]
}


#create function apps
resource "azurerm_service_plan" "timerstartpipelineapp" {
  name                = "timerstartpipelineapp-service-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "B1"
  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_application_insights" "timerstartpipelineapp" {
  name                = "TimerStartPipelineFunction-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_windows_function_app" "timerstartpipelineapp" {
  name                = "TimerStartPipelineFunction-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.timerstartpipelineapp.id
  depends_on = [azurerm_resource_group.rg, azurerm_storage_account.this, azurerm_service_plan.timerstartpipelineapp]

  identity {
    type = "UserAssigned"
    identity_ids = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.prefix}-RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.prefix}-msi"]
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  site_config {}

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "dotnet"
    APPINSIGHTS_INSTRUMENTATIONKEY=azurerm_application_insights.timerstartpipelineapp.instrumentation_key
    serviceBusNameSpace=azurerm_servicebus_namespace.this.name
    adxConnectionString=azurerm_kusto_cluster.this.uri
    metricsdbName=local.metricdb_name
    adxIngestionURI=azurerm_kusto_cluster.this.data_ingestion_uri
    queueName=local.queue_name
    rawDataContainerName=azurerm_storage_container.data.name
    storageAccountName=local.storage_account_name
    msiclientId=azurerm_user_assigned_identity.terraform.client_id
    MyTimeTrigger="0 */15 * * * *"
    msftTenantId="TenantId"
    keyVaultName=azurerm_key_vault.kv.name
	}
}

resource "null_resource" "dotnet_build_timerpipelineapp" {
  provisioner "local-exec" {
    command = local.dotnet_build_timerpipelineapp
  }
  triggers = {
    dotnet_build_command = local.dotnet_build_timerpipelineapp
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
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
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}

resource "zipper_file" "fixture1" {
  source             = "${path.cwd}/../../../../SchedulePipelineFunctionApp/bin/publish"
  output_path        = "${path.cwd}/../../../../SchedulePipelineFunctionApp/SchedulePipelineFunctionApp.zip"
  depends_on = [null_resource.dotnet_publish_timerpipelineapp]
  not_when_nonexists = false
}

resource "null_resource" "deploy_zip_app1" {
  provisioner "local-exec" {
    command = local.curl_zip_deploy_app1
  }
  depends_on = [zipper_file.fixture1, azurerm_windows_function_app.timerstartpipelineapp]
  triggers = {
    generate_azaccess_token = local.curl_zip_deploy_app1
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}


resource "null_resource" "disable_basic_auth_timerpipelineapp_scm" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_timerpipelineapp_scm
  }
  depends_on = [azurerm_windows_function_app.timerstartpipelineapp]
  triggers = {
    disable_basic_auth_timerpipelineapp_scm_command = local.disable_basic_auth_timerpipelineapp_scm
  }
}

resource "null_resource" "disable_basic_auth_timerpipelineapp_ftp" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_timerpipelineapp_ftp
  }
  depends_on = [azurerm_windows_function_app.timerstartpipelineapp]
  triggers = {
    disable_basic_auth_timerpipelineapp_ftp_command = local.disable_basic_auth_timerpipelineapp_ftp
  }
}
resource "azurerm_service_plan" "adxingestionapp" {
  name                = "adxingestionapp-service-plan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "B1"
  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_application_insights" "adxingestionapp" {
  name                = "AdxIngestFunction-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_windows_function_app" "adxingestionapp" {
  name                = "AdxIngestFunction-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.adxingestionapp.id
  depends_on = [azurerm_resource_group.rg, azurerm_storage_account.this, azurerm_service_plan.adxingestionapp]

  identity {
    type = "UserAssigned"
    identity_ids = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.prefix}-RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.prefix}-msi"]
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

  site_config {
    always_on = true
  }
  
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "dotnet"
    APPINSIGHTS_INSTRUMENTATIONKEY=azurerm_application_insights.adxingestionapp.instrumentation_key
    ServiceBusMSIConnection=local.serviceBusMSIString
    ServiceBusConnection__fullyQualifiedNamespace="${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"
    ServiceBusConnection__clientId=azurerm_user_assigned_identity.terraform.client_id
    adxConnectionString=azurerm_kusto_cluster.this.uri
    metricsdbName=local.metricdb_name
    adxIngestionURI=azurerm_kusto_cluster.this.data_ingestion_uri
    queueName=local.queue_name
    rawDataContainerName=azurerm_storage_container.data.name
    storageAccountName=local.storage_account_name
    msiclientId=azurerm_user_assigned_identity.terraform.client_id
    kustoMSIObjectId=azurerm_kusto_cluster.this.identity.0.principal_id
    keyVaultName=azurerm_key_vault.kv.name
    msftTenantId="TenantId"
    DefaultRequestHeaders="observabilitydashboard"
	}

}

resource "null_resource" "dotnet_build_adxingestapp" {
  provisioner "local-exec" {
    command = local.dotnet_build_adxingestapp
  }
  triggers = {
    dotnet_build_command = local.dotnet_build_adxingestapp
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}

resource "null_resource" "dotnet_publish_adxingestapp" {
  provisioner "local-exec" {
    command = local.dotnet_publish_adxingestapp
  }
  depends_on = [null_resource.dotnet_build_adxingestapp]
  triggers = {
    dotnet_build_command = local.dotnet_publish_adxingestapp
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}

resource "zipper_file" "fixture2" {
  source             = "${path.cwd}/../../../../AdxIngestFunctionApp/bin/publish"
  output_path        = "${path.cwd}/../../../../AdxIngestFunctionApp/AdxIngestFunctionApp.zip"
  depends_on = [null_resource.dotnet_publish_adxingestapp]
  not_when_nonexists = false
}

resource "null_resource" "deploy_zip_app2" {
  provisioner "local-exec" {
    command = local.curl_zip_deploy_app2
  }
  depends_on = [zipper_file.fixture2, azurerm_windows_function_app.adxingestionapp]
  triggers = {
    generate_azaccess_token = local.curl_zip_deploy_app2
  }
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }
}

resource "null_resource" "disable_basic_auth_adxingestapp_scm" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_adxingestapp_scm
  }
  depends_on = [azurerm_windows_function_app.adxingestionapp]
  triggers = {
    disable_basic_auth_adxingestapp_command = local.disable_basic_auth_adxingestapp_scm
  }
}

resource "null_resource" "disable_basic_auth_adxingestapp_ftp" {
  provisioner "local-exec" {
    command = local.disable_basic_auth_adxingestapp_ftp
  }
  depends_on = [azurerm_windows_function_app.adxingestionapp]
  triggers = {
    disable_basic_auth_adxingestapp_ftp_command = local.disable_basic_auth_adxingestapp_ftp
  }
}

resource "azurerm_dashboard_grafana" "this" {
  name                              = "${var.prefix}-grafana"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
  identity {
    type = "SystemAssigned"
  }
  depends_on = [azurerm_resource_group.rg, azurerm_storage_account.this, azurerm_kusto_cluster.this, azurerm_user_assigned_identity.terraform]
}

#assign contributor access to the sp for the resource group
resource "azurerm_role_assignment" "grafana_sp" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.this.object_id
  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_role_assignment" "sbsender" {
  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_storage_account.this, azurerm_user_assigned_identity.terraform]
}

resource "azurerm_role_assignment" "sbreceiver" {
  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_storage_account.this, azurerm_user_assigned_identity.terraform]
}

resource "azurerm_kusto_cluster_principal_assignment" "this" {
  name                = "KustoSpAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azuread_service_principal.this.client_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "AllDatabasesAdmin"
  depends_on = [azurerm_resource_group.rg,azurerm_kusto_cluster.this]
}

resource "azurerm_kusto_cluster_principal_assignment" "msi" {
  name                = "KustoMsiAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_user_assigned_identity.terraform.principal_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "AllDatabasesAdmin"
  depends_on = [azurerm_resource_group.rg,azurerm_kusto_cluster.this]
}

resource "azurerm_kusto_cluster_principal_assignment" "grafanamsi" {
  name                = "KustoGrafanaMsiAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_dashboard_grafana.this.identity.0.principal_id
  principal_type = "App"
  role           = "AllDatabasesAdmin"
  depends_on = [azurerm_resource_group.rg,azurerm_kusto_cluster.this]
}

resource "azurerm_kusto_cluster_principal_assignment" "user" {
  name                = "KustoUserAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = data.azurerm_client_config.current.object_id
  principal_type = "User"
  role           = "AllDatabasesAdmin"
  depends_on = [azurerm_resource_group.rg,azurerm_kusto_cluster.this]
}

resource "azurerm_kusto_database_principal_assignment" "this" {
  name                = "DatabaseSpAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name
  database_name       = azurerm_kusto_database.database.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azuread_service_principal.this.client_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "Admin"
  depends_on = [azurerm_kusto_database.database]
}

resource "azurerm_kusto_database_principal_assignment" "msi" {
  name                = "DatabaseMsiAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name
  database_name       = azurerm_kusto_database.database.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azurerm_user_assigned_identity.terraform.principal_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "Admin"
  depends_on = [azurerm_kusto_database.database]
}

#add permissions
resource "azurerm_role_assignment" "adx" {
  scope                = azurerm_kusto_cluster.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id#data.azurerm_client_config.current.object_id
  depends_on = [azurerm_kusto_cluster.this, azurerm_user_assigned_identity.terraform]
}

resource "azurerm_role_assignment" "storage" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_storage_account.this, azurerm_user_assigned_identity.terraform]
}

resource "azurerm_role_assignment" "database" {
  scope                = azurerm_kusto_database.database.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_kusto_database.database, azurerm_user_assigned_identity.terraform]
}

#add storage_blob_data_contributor to the storage account
resource "azurerm_role_assignment" "msi_storage_role" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_storage_account.this, azurerm_user_assigned_identity.terraform]
}

#add storage_blob_data_contributor to the storage account
resource "azurerm_role_assignment" "kusto_msi_storage_role" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kusto_cluster.this.identity.0.principal_id
  depends_on = [azurerm_storage_account.this, azurerm_kusto_cluster.this]
}

#add reader to the timerstartpipelineapp
resource "azurerm_role_assignment" "msi_timerstartpipelineapp_role" {
  scope                = azurerm_windows_function_app.timerstartpipelineapp.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_windows_function_app.timerstartpipelineapp, azurerm_user_assigned_identity.terraform]
}

#add reader to the adxingestapp
resource "azurerm_role_assignment" "msi_adxingestionapp_role" {
  scope                = azurerm_windows_function_app.adxingestionapp.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.terraform.principal_id
  depends_on = [azurerm_windows_function_app.adxingestionapp, azurerm_user_assigned_identity.terraform]
}

#assign grafana admin access to user
resource "azurerm_role_assignment" "grafanauser" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
  depends_on = [azurerm_dashboard_grafana.this]
}

#assign grafana admin access to msi
resource "azurerm_role_assignment" "grafanamsi" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = azurerm_dashboard_grafana.this.identity.0.principal_id
  depends_on = [azurerm_dashboard_grafana.this]
}

output "sp_object_id" {
  value                = azuread_service_principal.this.object_id
}

output "cluster_url" {
  value                = azurerm_kusto_cluster.this.uri
}

output "database_name" {
  value                = azurerm_kusto_database.database.name
}

output "client_config" {
  value =               data.azurerm_client_config.current.client_id
}

output "prefix" {
  value =               "${var.prefix}"
}
