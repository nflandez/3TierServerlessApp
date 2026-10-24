output "site_url" {
  description = "Open this in a browser"
  value       = module.frontend.site_url
}

output "api_url" {
  value = module.api.api_url
}

output "hosted_ui_domain" {
  description = "Cognito sign-in page domain"
  value       = module.auth.hosted_ui_domain
}

output "user_pool_id" {
  value = module.auth.user_pool_id
}

output "client_id" {
  value = module.auth.client_id
}

output "table_name" {
  value = module.data.table_name
}

output "dashboard_url" {
  value = module.monitoring.dashboard_url
}
