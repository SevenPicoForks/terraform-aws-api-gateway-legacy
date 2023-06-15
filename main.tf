locals {
  enabled                = module.this.enabled
  create_rest_api_policy = local.enabled && var.rest_api_policy != null
  create_log_group       = local.enabled && var.logging_level != "OFF"
  log_group_arn          = local.create_log_group ? module.cloudwatch_log_group.log_group_arn : null
  vpc_link_enabled       = local.enabled && length(var.private_link_target_arns) > 0
}

resource "aws_api_gateway_rest_api" "this" {
  count = local.enabled ? 1 : 0

  name           = module.this.id
  body           = jsonencode(var.openapi_config)
  tags           = module.this.tags
  api_key_source = var.api_key_source
  description    = var.api_gateway_description

  endpoint_configuration {
    types = [var.endpoint_type]
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_rest_api_policy" "this" {
  count       = local.create_rest_api_policy ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id

  policy = var.rest_api_policy
}

module "log_group_label" {
  source  = "registry.terraform.io/cloudposse/label/null"
  version = "0.25.0"

  # Allow forward slashes
  regex_replace_chars = "/[^a-zA-Z0-9-\\/]/"
  delimiter           = "/"
  namespace           = "/aws"
  stage               = "apigateway"
  name                = module.this.id
  enabled             = local.create_log_group
}

module "cloudwatch_log_group" {
  source  = "registry.terraform.io/cloudposse/cloudwatch-logs/aws"
  version = "0.6.2"

  context          = module.log_group_label.context
  iam_role_enabled = false
}

resource "aws_api_gateway_deployment" "this" {
  count       = local.enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this[0].body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  #checkov:skip=CKV_AWS_73:skipping 'Ensure API Gateway has X-Ray Tracing enabled' because it can be enabled through 'var.xray_tracing_enabled'
  #checkov:skip=CKV2_AWS_4:skipping 'Ensure API Gateway stage have logging level defined as appropriate' because it can be configured through variables
  #checkov:skip=CKV2_AWS_29:skipping 'Ensure public API gateway are protected by WAF'
  #checkov:skip=CKV2_AWS_51:skipping 'Ensure AWS API Gateway endpoints uses client certificate authentication'
  #checkov:skip=CKV_AWS_120:skipping 'Ensure API Gateway caching is enabled'
  count                = local.enabled ? 1 : 0
  deployment_id        = aws_api_gateway_deployment.this[0].id
  rest_api_id          = aws_api_gateway_rest_api.this[0].id
  stage_name           = module.this.stage
  xray_tracing_enabled = var.xray_tracing_enabled
  tags                 = module.this.tags

  variables = {
    vpc_link_id = local.vpc_link_enabled ? aws_api_gateway_vpc_link.this[0].id : null
  }

  dynamic "access_log_settings" {
    for_each = local.create_log_group ? [1] : []

    content {
      destination_arn = local.log_group_arn
      format          = replace(var.access_log_format, "\n", "")
    }
  }
}

# Set the logging, metrics and tracing levels for all methods
resource "aws_api_gateway_method_settings" "all" {
  #checkov:skip=CKV_AWS_225:skipping 'Ensure API Gateway method setting caching is enabled'
  #checkov:skip=CKV_AWS_308:skipping 'Ensure API Gateway method setting caching is set to encrypted'
  count       = local.enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.this[0].id
  stage_name  = aws_api_gateway_stage.this[0].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = var.metrics_enabled
    logging_level   = var.logging_level
  }
}

# Optionally create a VPC Link to allow the API Gateway to communicate with private resources (e.g. ALB)
resource "aws_api_gateway_vpc_link" "this" {
  count       = local.vpc_link_enabled ? length(var.private_link_target_arns) : 0
  name        = "${module.this.id} - ${count.index}"
  description = "Link to ${var.private_link_target_arns[count.index]}"
  target_arns = [var.private_link_target_arns[count.index]]
  tags        = module.this.tags
}
