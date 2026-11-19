###############################################################################
# VPC flow logs (optional - enabled in prod)
###############################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${local.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = local.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/vpc/${local.name}/flow-logs:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix        = "${substr(local.name, 0, 20)}-flow-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "flow-logs-"
  role        = aws_iam_role.flow_logs[0].id
  policy      = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(local.tags, {
    Name = "${local.name}-flow-logs"
  })
}
