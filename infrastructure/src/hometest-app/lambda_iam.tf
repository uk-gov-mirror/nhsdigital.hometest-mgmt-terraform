################################################################################
# Lambda IAM — Per-Lambda Roles (Least Privilege)
#
# IAM roles are now created INSIDE the modules/lambda module (iam.tf).
# Each Lambda function gets its own dedicated role with only the permissions
# it needs, specified via the `iam` block in the lambdas variable.
#
# The shared lambda-iam module is no longer used here.
#
# To see per-lambda IAM configuration, look at:
#   - modules/lambda/iam.tf         → IAM role & policy definitions
#   - lambda.tf (this dir)          → per-lambda IAM variable passthrough
#   - variables.tf (lambdas var)    → per-lambda IAM schema
#   - environments/*/app.hcl        → per-lambda IAM declarations
################################################################################
