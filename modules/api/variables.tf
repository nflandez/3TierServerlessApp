variable "name" {
  type = string
}

variable "table_name" {
  type = string
}

variable "table_arn" {
  type = string
}

variable "user_pool_issuer" {
  type = string
}

variable "client_id" {
  type = string
}

variable "allowed_origin" {
  description = "The only website origin allowed to call the API from a browser"
  type        = string
}

variable "log_retention_days" {
  type = number
}
