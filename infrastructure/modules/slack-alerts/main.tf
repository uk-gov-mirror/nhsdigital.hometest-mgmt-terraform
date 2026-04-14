################################################################################
# Slack Alerts Module
# Forwards SNS alarm notifications to Slack via an incoming webhook.
# The webhook URL is read from AWS Secrets Manager at runtime.
################################################################################

locals {
  resource_prefix = "${var.project_name}-${var.aws_account_shortname}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Name         = "${local.resource_prefix}-slack-notifier"
      Service      = "lambda"
      ManagedBy    = "terraform"
      Module       = "slack-alerts"
      ResourceType = "slack-notifier"
    }
  )
}

################################################################################
# Data sources
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret" "webhook" {
  name = var.slack_webhook_secret_name
}

################################################################################
# Lambda function — SNS → Slack forwarder
################################################################################

data "archive_file" "notifier" {
  type        = "zip"
  output_path = "${path.module}/lambda/slack-notifier.zip"

  source {
    content  = <<-HANDLER
const https = require('https');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const smClient = new SecretsManagerClient({});
let cachedWebhookUrl;

async function getWebhookUrl() {
  if (cachedWebhookUrl) return cachedWebhookUrl;
  const resp = await smClient.send(new GetSecretValueCommand({ SecretId: process.env.SECRET_NAME }));
  cachedWebhookUrl = resp.SecretString;
  return cachedWebhookUrl;
}

function severityFromTopic(topicArn) {
  if (topicArn.includes('critical')) return { label: 'CRITICAL', color: '#ff0000', emoji: ':rotating_light:' };
  if (topicArn.includes('security')) return { label: 'SECURITY', color: '#ff8c00', emoji: ':shield:' };
  if (topicArn.includes('warning'))  return { label: 'WARNING',  color: '#ffcc00', emoji: ':warning:' };
  return { label: 'INFO', color: '#36a64f', emoji: ':information_source:' };
}

function buildPayload(record) {
  const snsMessage = record.Sns;
  const topicArn   = snsMessage.TopicArn || '';
  const severity   = severityFromTopic(topicArn);
  const channel    = process.env.SLACK_CHANNEL || undefined;

  let alarmName = snsMessage.Subject || 'CloudWatch Alarm';
  let details   = '';

  try {
    const msg = JSON.parse(snsMessage.Message);
    alarmName = msg.AlarmName || alarmName;
    const state    = msg.NewStateValue || 'UNKNOWN';
    const reason   = msg.NewStateReason || '';
    const metric   = msg.Trigger ? msg.Trigger.MetricName : '';
    const ns       = msg.Trigger ? msg.Trigger.Namespace : '';
    details = [
      '*State:* \`' + state + '\`',
      metric ? '*Metric:* \`' + ns + '/' + metric + '\`' : '',
      reason ? '*Reason:* ' + reason.substring(0, 300) : '',
    ].filter(Boolean).join('\n');
  } catch (_) {
    details = snsMessage.Message ? snsMessage.Message.substring(0, 500) : '';
  }

  const payload = {
    attachments: [{
      color: severity.color,
      blocks: [
        { type: 'section', text: { type: 'mrkdwn', text: severity.emoji + ' *[' + severity.label + '] ' + alarmName + '*' } },
        { type: 'section', text: { type: 'mrkdwn', text: details } },
        { type: 'context', elements: [{ type: 'mrkdwn', text: 'Region: \`' + (process.env.AWS_REGION || 'eu-west-2') + '\` | Account: \`' + (process.env.AWS_ACCOUNT_ID || '') + '\` | Topic: \`' + topicArn.split(':').pop() + '\`' }] },
      ],
    }],
  };
  if (channel) payload.channel = channel;
  return payload;
}

function post(url, body) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request({ hostname: parsed.hostname, path: parsed.pathname, method: 'POST', headers: { 'Content-Type': 'application/json' } }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ statusCode: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.end(JSON.stringify(body));
  });
}

exports.handler = async (event) => {
  const webhookUrl = await getWebhookUrl();
  const results = [];
  for (const record of event.Records) {
    const payload = buildPayload(record);
    const resp = await post(webhookUrl, payload);
    console.log('Slack response', resp.statusCode, resp.body);
    results.push(resp);
  }
  return { statusCode: 200, body: JSON.stringify({ sent: results.length }) };
};
HANDLER
    filename = "index.js"
  }
}

resource "aws_lambda_function" "notifier" {
  function_name    = "${local.resource_prefix}-slack-notifier"
  description      = "Forwards SNS alarm notifications to Slack channel ${var.slack_channel_name}"
  filename         = data.archive_file.notifier.output_path
  source_code_hash = data.archive_file.notifier.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  timeout          = 15
  memory_size      = 128

  role = aws_iam_role.notifier.arn

  environment {
    variables = {
      SECRET_NAME    = var.slack_webhook_secret_name
      SLACK_CHANNEL  = var.slack_channel_name
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${aws_lambda_function.notifier.function_name}"
  retention_in_days = 30
  tags              = local.common_tags
}

################################################################################
# IAM Role for the Lambda
################################################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notifier" {
  name               = "${local.resource_prefix}-slack-notifier-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "notifier" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.resource_prefix}-slack-notifier:*"]
  }

  # Secrets Manager — read the webhook URL
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.webhook.arn]
  }

  # KMS — decrypt the secret (if encrypted with a CMK)
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "notifier" {
  name   = "${local.resource_prefix}-slack-notifier-policy"
  role   = aws_iam_role.notifier.id
  policy = data.aws_iam_policy_document.notifier.json
}

################################################################################
# SNS Subscriptions — each topic triggers the Lambda
################################################################################

resource "aws_sns_topic_subscription" "topics" {
  for_each = toset(var.sns_topic_arns)

  topic_arn = each.value
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}

resource "aws_lambda_permission" "sns" {
  for_each = toset(var.sns_topic_arns)

  statement_id  = "AllowSNS-${md5(each.value)}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value
}
