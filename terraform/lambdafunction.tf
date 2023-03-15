provider "aws" {
    region = "us-east-1"
}

resource "aws_iam_role" "lambda_role" {
    name = "counter_lambda_tf_role"
    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "lambda.amazonaws.com"
          }
       }
     ]
  })
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
    name = "iam_policy_for_counter_lambda_tf_role"
    path = "/"
    description = "AWS IAM policy for managing aws lambda role"
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Action": "dynamodb:*",
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
EOF
}


# Policy Attachment on the role.

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
    role = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

# Generates an archive from content from Source_directory

data "archive_file" "zip_the_python_code" {
    type = "zip"
    source_dir = "${path.module}/python/"
    output_path = "${path.module}/python/visitorCount.zip"
}

# Create a lambda function
# In terraform ${path.module} is the current directory.
resource "aws_lambda_function" "terraform_lambda_func" {
    filename = "${path.module}/python/visitorCount.zip"
    function_name = "visitorCount_lambda_function"
    role = aws_iam_role.lambda_role.arn
    handler = "visitorCount.lambda_handler"
    runtime = "python3.9"
    depends_on = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}

output "terraform_aws_role_output" {
    value = aws_iam_role.lambda_role.name
}
output "terraform_aws_role_arn_output" {
    value = aws_iam_role.lambda_role.arn
}



# API-GATEWAY

resource "aws_lambda_permission" "counter_api_gateway_permission" {
    statement_id = "AllowLambdaExecutionFromAPIGateway"
    action = "lambda:InvokeFunction"
    function_name = "visitorCount_lambda_function"
    principal = "apigateway.amazonaws.com"
}

resource "aws_api_gateway_rest_api" "counter-api-gateway" {
    name = "counter-api-gateway"
    endpoint_configuration {
      types = ["REGIONAL"]
    }
}

resource "aws_api_gateway_resource" "counter" {
    rest_api_id = aws_api_gateway_rest_api.counter-api-gateway.id
    parent_id = aws_api_gateway_rest_api.counter-api-gateway.root_resource_id
    path_part = "counter"
}

# POST Method

resource "aws_api_gateway_method" "post" {
    rest_api_id = aws_api_gateway_rest_api.counter-api-gateway.id
    resource_id = aws_api_gateway_resource.counter.id
    http_method = "POST"
    authorization = "NONE"
    api_key_required = false
}

resource "aws_api_gateway_integration" "integration" {
    rest_api_id = aws_api_gateway_rest_api.counter-api-gateway.id
    resource_id = aws_api_gateway_resource.counter.id
    http_method = aws_api_gateway_method.post.http_method
    integration_http_method = "POST"
    type = "AWS_PROXY"
    uri = aws_lambda_function.terraform_lambda_func.invoke_arn
}

# Deployment and Stage

resource "aws_api_gateway_deployment" "deployment1" {
    rest_api_id = aws_api_gateway_rest_api.counter-api-gateway.id
    depends_on = [aws_api_gateway_integration.integration]
    lifecycle {
      create_before_destroy = true
    }
}

resource "aws_api_gateway_stage" "dev" {
    deployment_id = aws_api_gateway_deployment.deployment1.id
    rest_api_id = aws_api_gateway_rest_api.counter-api-gateway.id
    stage_name = "prod"
}

output "invoke_arn" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}"}
output "stage_name" {value = "${aws_api_gateway_stage.dev.stage_name}"}
output "path_part" {value = "${aws_api_gateway_resource.counter.path_part}"}
output "complete_unvoke_url" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}${aws_api_gateway_stage.dev.stage_name}/${aws_api_gateway_resource.counter.path_part}"}


# DYNAMODB

resource "aws_dynamodb_table" "DynamoDBTable" {
    attribute {
        name = "visitor_id"
        type = "S"
    }
    billing_mode = "PAY_PER_REQUEST"
    name = "visitor_count2"
    hash_key = "visitor_id"
}