variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-1"
}

variable "name" {
  description = "Name prefix for all resources (lowercase letters, numbers and hyphens)"
  type        = string
  default     = "taskapp"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps Lambda and API Gateway logs"
  type        = number
  default     = 14
}
