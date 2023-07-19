# export TF_VAR_token=$(az grafana api-key create --key `date +%s` --name grafana02-grafana -g grafana02-RG -r editor --time-to-live 4m -o json | jq -r .key)
variable "token" {
  type      = string
  nullable  = false
  sensitive = true
}

# export TF_VAR_url=$(az grafana show -g grafana02-RG -n grafana02-grafana -o json | jq -r .properties.endpoint)
variable "url" {
  type      = string
  nullable  = false
  sensitive = false
}

#export TF_VAR_prefix=$(terraform output -raw prefix)
variable "prefix" {
  type      = string
  nullable  = false
  sensitive = false
}