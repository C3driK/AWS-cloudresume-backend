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

resource "aws_dynamodb_table" "DynamoDBTable" {
    attribute {
        name = "visitor_id"
        type = "S"
    }
    billing_mode = "PAY_PER_REQUEST"
    name = "visitor_count2"
    hash_key = "visitor_id"
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
resource "aws_lambda_function" "visitorCount_lambda_function" {
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

resource "aws_lambda_permission" "lambda_permission" {
    statement_id   = "AllowCounterAPIInvoke"
    action         = "lambda:InvokeFunction"
    function_name  = "visitorCount_lambda_function"
    principal      = "apigateway.amazonaws.com"

    source_arn = "${aws_api_gateway_rest_api.CounterAPI.execution_arn}/*"
}

# API-GATEWAY

resource "aws_api_gateway_rest_api" "CounterAPI" {
  name = "CounterAPI"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "visits" {
    parent_id    = aws_api_gateway_rest_api.CounterAPI.root_resource_id
    rest_api_id  = aws_api_gateway_rest_api.CounterAPI.id
    path_part    = "visits"
}

resource "aws_api_gateway_method" "post" {
    authorization    = "NONE"
    http_method      = "ANY"
    resource_id      = aws_api_gateway_resource.visits.id
    rest_api_id      = aws_api_gateway_rest_api.CounterAPI.id 
    api_key_required = false
    request_parameters = {}
}

resource "aws_api_gateway_integration" "integrate1" {
    http_method             = aws_api_gateway_method.post.http_method
    resource_id             = aws_api_gateway_resource.visits.id
    rest_api_id             = aws_api_gateway_rest_api.CounterAPI.id
    type                    = "AWS_PROXY"
    integration_http_method = "ANY"
    uri                     = aws_lambda_function.visitorCount_lambda_function.invoke_arn 
}

resource "aws_api_gateway_deployment" "deployment1" {
  rest_api_id = aws_api_gateway_rest_api.CounterAPI.id

  triggers = {
    redeployment = sha1(jsonencode([
        aws_api_gateway_resource.visits.id,
        aws_api_gateway_method.post.id,
        aws_api_gateway_integration.integrate1.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_api_gateway_stage" "prod" {
    deployment_id = aws_api_gateway_deployment.deployment1.id
    rest_api_id   = aws_api_gateway_rest_api.CounterAPI.id
    stage_name    = "prod"
    disable_execute_api_endpoint = false
}







output "invoke_arn" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}"}
output "stage_name" {value = "${aws_api_gateway_stage.prod.stage_name}"}
output "path_part" {value = "${aws_api_gateway_resource.visits.path_part}"}
output "complete_unvoke_url" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}${aws_api_gateway_stage.prod.stage_name}/${aws_api_gateway_resource.visits.path_part}"}



