variable "region" {
  default = "europe-west1"
}

variable "region_zone" {
  default = "europe-west1-d"
}

variable "project_name" {
  description = "dummy_project"
}

variable "aws_region" {
  type        = "string"
  description = "AWS region for S3 bucket"
  default     = ""
}

variable "aws_access_key" {
  type        = "string"
  description = "The access key for S3 bucket account"
  default     = ""
}

variable "aws_secret_key" {
  type        = "string"
  description = "The secrete key for S3 bucket account"
  default     = ""
}

variable "project_dns_name" {
  type        = "string"
  description = "The hosting zone our frontend hosts will be known on"
  default     = "byteless.net."
}

variable "project_a_record" {
  type        = "string"
  description = "The A record"
  default     = "grb"
}

variable "credentials_file_path" {
  description = "Path to the JSON file used to describe your account credentials"
  default = "~/.gcloud/Terraform.json"
}

variable "public_key_path" {
  description = "Path to file containing public key"
  default = "~/.ssh/gcloud_id_rsa.pub"
}

variable "private_key_path" {
  description = "Path to file containing private key"
  default = "~/.ssh/gcloud_id_rsa"
}

variable "install_script_src_path" {
  description = "Path to install script within this repository"
  default = "scripts/install.sh"
}

variable "install_script_dest_path" {
  description = "Path to put the install script on each destination resource"
  default = "/tmp/install.sh"
}

