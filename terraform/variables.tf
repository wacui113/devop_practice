variable "aws_region" {
description = "AWS region to deploy resources."
type = string
default = "us-east-2" 
}
variable "project_name" {
  description = "devops_course"
  type        = string
  default     = "coffeeshop"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"] 
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"] 
}

variable "availability_zones" {
  description = "List of Availability Zones to use."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"] 
}
