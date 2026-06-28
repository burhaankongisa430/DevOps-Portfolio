variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID from Project 1"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes and control-plane ENIs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs — tagged so the AWS LBC can place internet-facing ALBs here"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "EC2 instance type for managed node group. t3.micro is too small for k8s; t3.medium (4 GiB) is the minimum for stable workloads."
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  description = "Minimum nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum nodes in the managed node group"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Initial desired node count"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for each node"
  type        = number
  default     = 20
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks that can reach the public cluster API endpoint. Restrict to your IP for prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_log_types" {
  description = "EKS control-plane log types to send to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "aws_lbc_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.7.2"
}
