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

#access the configuration of the AzureRM provider - current user credentials
data "azurerm_client_config" "current" {}
data azuread_client_config "current" {}
data "azurerm_subscription" "primary" {
}

#create ad application
resource "azuread_application" "this" {
  display_name = "${var.prefix}-sp"
  owners       = [data.azuread_client_config.current.object_id]
}

#create a service principal tagged to ad application
resource "azuread_service_principal" "this" {
  application_id               = azuread_application.this.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

#create the secret for the service principal
resource "azuread_service_principal_password" "this" {
  service_principal_id = azuread_service_principal.this.object_id
}

#create resource group to house resources
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-RG"
  location = "${var.location}"
}

#create a kusto cluster
resource "azurerm_kusto_cluster" "this" {
  name                = "${var.prefix}adx"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name     = "Dev(No SLA)_Standard_E2a_v4"
    capacity = 1
  }

  depends_on = [azurerm_resource_group.rg]

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
  soft_delete_period = "P31D"
}

resource "azurerm_dashboard_grafana" "this" {
  name                              = "${var.prefix}-grafana"
  resource_group_name               = azurerm_resource_group.rg.name
  location                          = azurerm_resource_group.rg.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
}

#assign contributor access to the sp for the resource group
resource "azurerm_role_assignment" "grafana_sp" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.this.object_id
}

resource "azurerm_kusto_cluster_principal_assignment" "this" {
  name                = "KustoSpAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azuread_service_principal.this.application_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "AllDatabasesAdmin"
}

resource "azurerm_kusto_database_principal_assignment" "this" {
  name                = "DatabaseSpAssignment"
  resource_group_name = azurerm_resource_group.rg.name
  cluster_name        = azurerm_kusto_cluster.this.name
  database_name       = azurerm_kusto_database.database.name

  tenant_id      = data.azurerm_client_config.current.tenant_id
  principal_id   = azuread_service_principal.this.application_id#data.azurerm_client_config.current.client_id
  principal_type = "App"
  role           = "Admin"
}

output "sp_object_id" {
  value                = azuread_service_principal.this.object_id
}

output "cluster_url" {
  value                = azurerm_kusto_cluster.this.uri
}

output "sp_client_id" {
  value                = azuread_service_principal.this.application_id#
}

output "sp_client_secret" {
  value                = azuread_service_principal_password.this.value
  sensitive            = true
}

output "tenant_id" {
  value                = data.azuread_client_config.current.tenant_id
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





/*resource "azapi_resource" "grafana" {
  type = "Microsoft.Dashboard/grafana@2022-08-01"
  name = "${var.prefix}-grafana"
  location = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id
  tags = {
    tagName1 = "grafana-resource"
  }
  body = jsonencode({
    properties = {
      apiKey = "Enabled"
      autoGeneratedDomainNameLabelScope = "TenantReuse"
      deterministicOutboundIP = "Enabled"
      grafanaIntegrations = {
        azureMonitorWorkspaceIntegrations = [
          {
            azureMonitorWorkspaceResourceId = "string"
          }
        ]
      }
      publicNetworkAccess = "string"
      zoneRedundancy = "string"
    }
    sku = {
      name = "string"
    }
  })
}*/

/*resource "azapi_resource" "azdataexplorer" {
  type      = "Microsoft.Kusto/clusters/databases/dataConnections@2022-12-29"
  name      = "azure-data-explorer-aks"
  parent_id = azurerm_kusto_cluster.this.id
  location  = azurerm_resource_group.rg.location

  response_export_values = ["*"]
}*/