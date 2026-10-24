variable "name" {
  type = string
}

variable "domain_prefix" {
  description = "Globally unique prefix for the Cognito hosted UI domain"
  type        = string
}

variable "site_url" {
  description = "HTTPS URL of the frontend, used for sign-in and sign-out redirects"
  type        = string
}
