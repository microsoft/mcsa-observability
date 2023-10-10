variable "prefix" {
  type        = string
  description = "The prefix that is used to identify resources and tag them"
}

variable "subscriptionId" {
  type        = string
  description = "The Id of the subscription where the user wants to deploy the resources"
}

variable "location" {
  type        = string
  description = "The location where the user wants to deploy the resources"
}

variable "aoaiusagedashboard" {
  type        = bool
  description = "Enter true to deploy aoai usage dashboard, else enter false"
}