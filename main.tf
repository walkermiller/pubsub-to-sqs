resource "google_pubsub_topic" "sqs" {
  name = "sqs-test"
}

resource "google_pubsub_topic" "dead_letter" {
  name = "deadletter"
}
resource "aws_sqs_queue" "pubsub" {
    name = "pubsub"
}


resource "aws_api_gateway_rest_api" "sqs" {
    name = "sqs"
}

resource "aws_iam_role" "sqs" {
    managed_policy_arns = [data.aws_iam_policy.AmazonSQSFullAccess.arn]
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  
}

resource "aws_api_gateway_method" "sqs-root" {
    authorization = "NONE"
    http_method = "POST"
    resource_id = aws_api_gateway_rest_api.sqs.root_resource_id
    rest_api_id = aws_api_gateway_rest_api.sqs.id 
}

resource "aws_api_gateway_integration" "sqs" {
  http_method = aws_api_gateway_method.sqs-root.http_method
  resource_id = aws_api_gateway_rest_api.sqs.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.sqs.id
  type        = "AWS"
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.pubsub.name}"
  integration_http_method = aws_api_gateway_method.sqs-root.http_method
  credentials = aws_iam_role.sqs.arn
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
  

}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.sqs.id
  resource_id = aws_api_gateway_rest_api.sqs.root_resource_id
  http_method = aws_api_gateway_method.sqs-root.http_method
  status_code = "200"
  response_models = {
    "application/json"  = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "SQSResponse" {
  rest_api_id = aws_api_gateway_rest_api.sqs.id
  resource_id = aws_api_gateway_rest_api.sqs.root_resource_id
  http_method = aws_api_gateway_method.sqs-root.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
}


resource "aws_api_gateway_deployment" "sqs" {
  rest_api_id = aws_api_gateway_rest_api.sqs.id

  triggers = {

    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.sqs.root_resource_id,
      aws_api_gateway_method.sqs-root,
      aws_api_gateway_integration.sqs,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.sqs.id
  rest_api_id   = aws_api_gateway_rest_api.sqs.id
  stage_name    = "prod"
}


resource "google_pubsub_subscription" "sqs" {
  name  = "sqs-subscription"
  topic = google_pubsub_topic.sqs.name


  ack_deadline_seconds = 60
  dead_letter_policy {
    dead_letter_topic = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  push_config {
    push_endpoint = aws_api_gateway_stage.prod.invoke_url

    attributes = {
      x-goog-version = "v1"
    }
  }
}