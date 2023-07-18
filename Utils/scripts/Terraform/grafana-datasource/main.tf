terraform {
  backend "azurerm" {
      resource_group_name  = "tfstate"
      storage_account_name = "<storage_account_name>"
      container_name       = "tfstate"
      key                  = "terraform.tfstate"
  }
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