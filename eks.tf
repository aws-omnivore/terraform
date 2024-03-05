data "aws_caller_identity" "current" {}

locals {
  node_group_name        = "${var.cluster_name}-node-group"
  iam_role_policy_prefix = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy"
}



module "eks" {
  # 모듈 사용
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # 관리형 노드 그룹 사용 (기본 설정)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64" # 
    disk_size      = 80           # EBS 사이즈
    instance_types = ["m7i.large"]
    vpc_security_group_ids = [aws_security_group.Food-sg.id]
  }
# 관리형 노드 그룹 사용 (노드별 추가 설정)
  eks_managed_node_groups = {
    ("${var.cluster_name}-group") = {
      # node group 스케일링
      min_size     = 1 # 최소
      max_size     = 5 # 최대
      desired_size = 2 # 기본 유지

      # 생성된 node에 labels 추가 (kubectl get nodes --show-labels로 확인 가능)
      labels = {
        ondemand = "true"
      }

      # 생성되는 인스턴스에 tag추가
      tags = {
        "k8s.io/cluster-autoscaler/enabled" : "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" : "true"
      }
    }
  }
}

locals {
  lb_controller_iam_role_name        = "inhouse-eks-aws-lb-ctrl"
  lb_controller_service_account_name = "aws-load-balancer-controller"
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.this.token
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  }
}

module "lb_controller_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"

  create_role = true

  role_name        = local.lb_controller_iam_role_name
  role_path        = "/"
  role_description = "Used by AWS Load Balancer Controller for EKS"

  role_permissions_boundary_arn = ""

  provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  oidc_fully_qualified_subjects = [
    "system:serviceaccount:kube-system:${local.lb_controller_service_account_name}"
  ]
  oidc_fully_qualified_audiences = [
    "sts.amazonaws.com"
  ]
}

data "http" "iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json"
}

data "http" "argocd-json" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

resource "aws_iam_role_policy" "controller" {
  name_prefix = "AWSLoadBalancerControllerIAMPolicy"
  policy      = data.http.iam_policy.body
  role        = module.lb_controller_role.iam_role_name
}

resource "helm_release" "release" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"

  dynamic "set" {
    for_each = {
      "clusterName"                                               = "Food-cluster"
      "serviceAccount.create"                                     = "true"
      "serviceAccount.name"                                       = local.lb_controller_service_account_name
      "region"                                                    = "ap-northeast-2"
      "vpcId"                                                     = module.vpc.vpc_id
      "image.repository"                                          = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller"
      "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = "arn:aws:iam::825958448855:role/inhouse-eks-aws-lb-ctrl"
      #module.lb_controller_role.iam_role_arn
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}




resource "kubernetes_deployment" "echo" {
  metadata {
    name = "echo"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "echo"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "echo"
        }
      }
      spec {
        container {
          image = "k8s.gcr.io/echoserver:1.10"
          name  = "echo"
        }
      }
    }
  }
}

resource "kubernetes_service" "echo" {
  metadata {
    name = "echo"
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "echo"
    }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "alb" {
  metadata {
    name = "alb"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing",
      "alb.ingress.kubernetes.io/target-type" = "ip",
    }
  }
  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          backend {
            service {
              name = "echo"
              port {
                number = 8080
              }
            }
          }
          path = "/*"
        }
      }
    }
  }
}