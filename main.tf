terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.11.0"
    }
  }
}


provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Terraform = "true"
      Project   = "${var.cluster_name}-project"
    }
  }
}