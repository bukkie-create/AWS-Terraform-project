variable "project_name" {
  default = "learning-project"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "api_domain_name" {
  description = "Example: api.example.com"
  type        = string
  default     = ""
}

variable "api_certificate_arn" {
  description = "ACM certificate ARN for the API custom domain"
  type        = string
  default     = ""
}

variable "enable_shield_advanced" {
  default = false
}