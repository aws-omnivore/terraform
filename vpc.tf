# vpc.tf
locals {
  name = "new-food"

  public_cidr_blocks  = ["10.0.0.0/20", "10.0.16.0/20"]
  private_cidr_blocks = ["10.0.128.0/20", "10.0.144.0/20"]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  azs  = [var.azs[0], var.azs[1]]
  cidr = var.vpc_cidr

  # NAT게이트웨이를 생성합니다.
  enable_nat_gateway = true
  # NAT게이트웨이를 1개만 생성합니다.
  single_nat_gateway      = true
  enable_dns_hostnames    = true
  map_public_ip_on_launch = true


  # Public 서브넷에만 map_public_ip_on_launch 설정
  public_subnets = [
    local.public_cidr_blocks[0],
    local.public_cidr_blocks[1]
  ]


  private_subnets = [local.private_cidr_blocks[0], local.private_cidr_blocks[1]]



  nat_eip_tags = {         # 탄력적 ip
    Name = "Food-eip"
  }

  nat_gateway_tags = {
    Name = "Food-nat"
  }

  igw_tags = {
    Name = "Food-igw"
  }

  public_subnet_tags = {
    Name                                        = "Food-public-subnet"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1" # internet-facing
  }

  private_subnet_tags = {
    Name                                        = "Food-private-subnet"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1" # internal
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

resource "aws_security_group" "Food-sg" {
  name   = "Food-sg-all"
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "Food-sg-all"
  }

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}