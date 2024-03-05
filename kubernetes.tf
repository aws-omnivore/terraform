data "aws_eks_cluster_auth" "this1" {
  name = var.cluster_name
}

provider "kubernetes" {
  alias                  = "argo"
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.this1.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

##### recommend yamldecode #####
resource "kubernetes_manifest" "recommend_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/recommend_ingress.yml"))
}

##### recommend namespace #####
resource "kubernetes_namespace" "recommend" {
  metadata {
    name = "fs-recommend"
  }
}

##### translate yamldecode #####
resource "kubernetes_manifest" "translate_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/translate_ingress.yml"))
}

##### translate namespace #####
resource "kubernetes_namespace" "translate" {
  metadata {
    name = "fs-translate"
  }
}

##### recent yamldecode #####
resource "kubernetes_manifest" "recent_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/recent_ingress.yml"))
}

##### recent namespace #####
resource "kubernetes_namespace" "recent" {
  metadata {
    name = "fs-recent"
  }
}

##### extract yamldecode #####
resource "kubernetes_manifest" "extract_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/extract_ingress.yml"))
}

##### extract namespace #####
resource "kubernetes_namespace" "extract" {
  metadata {
    name = "fs-extract"
  }
}

##### bookmark yamldecode #####
resource "kubernetes_manifest" "bookmark_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/bookmark_ingress.yml"))
}

##### bookmark namespace #####
resource "kubernetes_namespace" "bookmark" {
  metadata {
    name = "fs-bookmark"
  }
}


##### argocd namespace #####
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

##### argocd ingress #####
resource "kubernetes_manifest" "argo_ingress" {
  provider = kubernetes
  manifest = yamldecode(file("./yml/argo_ingress.yml"))
}

##### argocd #####
resource "helm_release" "argocd" {
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "3.26.0" // 사용하려는 ArgoCD 버전
  namespace        = "argocd"
  name             = "argocd"
  create_namespace = true

  set {
    name  = "server.extraArgs.insecure"
    value = "true"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.argocd
  ]
}
