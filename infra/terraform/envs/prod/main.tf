#+#+#+#+###############################################################################
# PROD ROOT MODULE
#
# Terraform loads all *.tf files in this folder. This file is intentionally kept
# minimal; configuration is split into focused files for maintainability:
# - providers.tf, locals.tf, data.tf
# - vpc.tf, vpc-endpoints.tf, security-groups.tf
# - acm-cloudfront.tf, acm-alb.tf, static-sites.tf, deployments-bucket.tf
# - cicd-iam.tf, iam.tf
# - rds.tf, ssm-params.tf
# - alb.tf, asg-backend-api.tf
# - route53.tf, cloudwatch.tf
################################################################################
