################################################################################
# Aurora PostgreSQL Module
################################################################################

locals {
  # Common tags for cost allocation and resource management
  common_tags = merge(
    var.tags,
    {
      # Resource identification
      Name = var.identifier

      # Technical metadata
      Service       = "aurora"
      Engine        = "postgresql"
      EngineVersion = var.engine_version

      # Management metadata
      ManagedBy = "terraform"
      Module    = "aurora-postgres"

      # Cost allocation
      CostCenter = try(var.tags["CostCenter"], "")
      Owner      = try(var.tags["Owner"], "")
    }
  )

  # Resource-specific tags
  security_group_tags = merge(
    local.common_tags,
    {
      Name         = "${var.identifier}-sg"
      ResourceType = "security-group"
    }
  )

  db_instance_tags = merge(
    local.common_tags,
    {
      ResourceType     = "db-instance"
      StorageEncrypted = tostring(var.storage_encrypted)
    }
  )

  db_subnet_group_tags = merge(
    local.common_tags,
    {
      Name         = "${var.identifier}-subnet-group"
      ResourceType = "db-subnet-group"
    }
  )
}

################################################################################
# Aurora PostgreSQL Instance
################################################################################

module "aurora_postgres" {
  #checkov:skip=CKV_TF_1:Using a commit hash for module from the Terraform registry is not applicable
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> v10.2.0" # https://github.com/terraform-aws-modules/terraform-aws-rds-aurora/releases

  name                          = var.identifier
  engine                        = "aurora-postgresql"
  engine_version                = var.engine_version
  master_username               = var.username
  manage_master_user_password   = var.manage_master_user_password
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id
  database_name                 = var.db_name
  port                          = 5432

  vpc_id                 = var.vpc_id
  db_subnet_group_name   = var.db_subnet_group_name
  create_security_group  = false
  vpc_security_group_ids = [module.security_group.security_group_id]

  apply_immediately   = var.apply_immediately
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  serverlessv2_scaling_configuration = {
    min_capacity = var.serverlessv2_min_capacity
    max_capacity = var.serverlessv2_max_capacity
  }

  cluster_instance_class = "db.serverless"

  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  iam_database_authentication_enabled = var.enable_iam_auth
  enable_http_endpoint                = var.enable_http_endpoint

  cluster_parameter_group = {
    name        = "${var.identifier}-cluster-pg"
    family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
    description = "Cluster parameter group for ${var.identifier} - enforces TLS 1.2"
    parameters = [
      {
        name         = "rds.force_ssl"
        value        = "1"
        apply_method = "pending-reboot"
      }
    ]
  }

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window

  instances = {
    for i in range(1, var.number_of_instances + 1) : i => {}
  }

  tags = local.db_instance_tags
}
