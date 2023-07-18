terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.10"
    }
    grafana = {
      source = "grafana/grafana"
      version = "1.36.1"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# https://learn.microsoft.com/en-gb/azure/managed-grafana/how-to-api-calls
provider "grafana" {
  url = var.url
  auth = var.token
}

locals {
dashboard_templates = "${path.cwd}/../../dashboard_templates"
addperm_2 = "chmod 755 ${path.cwd}/../../update_drilldown.sh"
update_drilldowns = "${path.cwd}/../../update_drilldown.sh ${var.prefix} ${local.dashboard_templates}"
}

resource "grafana_folder" "observability" {
  title = "Observability_Dashboard"
}

resource "grafana_dashboard" "resource_observability" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/AzureResourceObservability.json")
}

resource "grafana_dashboard" "aks_server_node" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/AksServerNode.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "cosmos_db" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/CosmosDB.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "firewalls" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Firewalls.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "keyvault" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Keyvault.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "loadbalancer" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Loadbalancer.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "storage" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Storage.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "eventhubs" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Eventhubs.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "containerregistry" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/ContainerRegistry.json")
  depends_on = [grafana_dashboard.resource_observability]
}

resource "grafana_dashboard" "cognitiveservices" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/CognitiveServices.json")
  depends_on = [grafana_dashboard.resource_observability]
}

//add permission to execute the file
resource "null_resource" "add_perm_2" {
  provisioner "local-exec" {
    command = local.addperm_2
  }
  triggers = {
    addperm2 = local.addperm_2
  }
  depends_on = [grafana_dashboard.storage,grafana_dashboard.loadbalancer,grafana_dashboard.keyvault,grafana_dashboard.firewalls,grafana_dashboard.cosmos_db,grafana_dashboard.aks_server_node,grafana_dashboard.resource_observability,grafana_dashboard.eventhubs,grafana_dashboard.cognitiveservices,grafana_dashboard.containerregistry]
}

//update uid of datasource on the dashboards
resource "null_resource" "update_dashboard_datasourceuid" {
  provisioner "local-exec" {
    command = local.update_drilldowns
  }
  depends_on = [null_resource.add_perm_2]
  triggers = {
    datasourceuid_update = local.update_drilldowns
  }
}