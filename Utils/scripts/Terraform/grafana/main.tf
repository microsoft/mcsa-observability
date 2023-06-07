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
addperm_1 = "chmod 755 ${path.cwd}/../../grafana-datasource.sh"
addperm_2 = "chmod 755 ${path.cwd}/../../update_drilldown.sh"
create_datasource = "${path.cwd}/../../grafana-datasource.sh ${var.prefix} ${var.cluster_url} ${var.tenant_id} ${var.sp_client_id} ${var.sp_client_secret} ${var.database_name} ${local.dashboard_templates}"
update_drilldowns = "${path.cwd}/../../update_drilldown.sh ${var.prefix} ${local.dashboard_templates}"
}

resource "grafana_folder" "observability" {
  title = "Observability_Dashboard"
}

//add permission to execute the file
resource "null_resource" "add_perm_1" {
  provisioner "local-exec" {
    command = local.addperm_1
  }
  triggers = {
    addperm_1 = local.addperm_1
  }
}

//create datasource
resource "null_resource" "datasource_create" {
  provisioner "local-exec" {
    command = local.create_datasource
  }
 depends_on = [null_resource.add_perm_1]
  triggers = {
    grafana_datasource = local.create_datasource
  }
}

resource "grafana_dashboard" "resource_observability" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/AzureResourceObservability-1679088842231.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "aks_server_node" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/AksServerNode-1679088882867.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "cosmos_db" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/CosmosDB-1679088907885.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "firewalls" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Firewalls-1679088928078.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "keyvault" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Keyvault-1679088939482.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "loadbalancer" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Loadbalancer-1679088952762.json")
  depends_on = [null_resource.datasource_create]
}

resource "grafana_dashboard" "storage" {
  folder     = grafana_folder.observability.id
  overwrite = true
  config_json = file("../../dashboard_templates/Storage-1679088963314.json")
  depends_on = [null_resource.datasource_create]
}

//add permission to execute the file
resource "null_resource" "add_perm_2" {
  provisioner "local-exec" {
    command = local.addperm_2
  }
  triggers = {
    addperm2 = local.addperm_2
  }
  depends_on = [grafana_dashboard.storage,grafana_dashboard.loadbalancer,grafana_dashboard.keyvault,grafana_dashboard.firewalls,grafana_dashboard.cosmos_db,grafana_dashboard.aks_server_node,grafana_dashboard.resource_observability]
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