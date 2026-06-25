# variables.tf

# ##############################
# Project Metadata
# ##############################
variable "project_name" {
  type    = string
  default = "multi-cloud-k8s"
}

# ##############################
# Environemnt
# ##############################
variable "env" {
  type = string
}

# ##############################
# AWS
# ##############################
variable "aws_region" {
  type = string
}

# ##############################
# Azure
# ##############################
variable "az_location" {
  type = string
}
