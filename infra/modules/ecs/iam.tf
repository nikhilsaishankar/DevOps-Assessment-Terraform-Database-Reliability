###############################################################################
# IAM
#
# Two roles, deliberately separate:
#
#   execution role - used by the ECS agent itself, before the container starts,
#                    to pull the image, create log streams and read the database
#                    secret.
#   task role      - the identity the application code runs as. It gets nothing
#                    by default; ECS Exec permissions are added only when
#                    enable_execute_command is true.
###############################################################################

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name_prefix        = "${substr(local.name, 0, 16)}-exec-"
  description        = "ECS agent role for ${local.name}: image pull, logs, secret read."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read access to exactly one secret - not secretsmanager:* on all resources.
data "aws_iam_policy_document" "read_db_secret" {
  count = var.inject_db_secret ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "read_db_secret" {
  count = var.inject_db_secret ? 1 : 0

  name_prefix = "read-db-secret-"
  role        = aws_iam_role.execution.id
  policy      = data.aws_iam_policy_document.read_db_secret[0].json
}

resource "aws_iam_role" "task" {
  name_prefix        = "${substr(local.name, 0, 16)}-task-"
  description        = "Application identity for ${local.name}."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "ecs_exec" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_exec" {
  count = var.enable_execute_command ? 1 : 0

  name_prefix = "ecs-exec-"
  role        = aws_iam_role.task.id
  policy      = data.aws_iam_policy_document.ecs_exec[0].json
}
