variable "db_username" {
  description = "Master username for the RDS database"
  type = string
  sensitive = false
}

variable "db_password" {
  description = "Master password for the RDS database"
  type = string
  sensitive = true
}
