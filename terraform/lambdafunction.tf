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
resource "aws_dynamodb_table_item" "visitor_count" {
  table_name = aws_dynamodb_table.DynamoDBTable.name
  hash_key   = aws_dynamodb_table.DynamoDBTable.hash_key

  item = <<ITEM
  {
    "visitor_id": {"S": "Quantity"},
    "viewCount": {"N":"0"}
  }
ITEM
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
    path_part    = "CounterAPI"
}

resource "aws_api_gateway_method" "options" {
    authorization    = "NONE"
    http_method      = "OPTIONS"
    resource_id      = aws_api_gateway_resource.visits.id
    rest_api_id      = aws_api_gateway_rest_api.CounterAPI.id 
    api_key_required = false
}

resource "aws_api_gateway_method_response" "options" {
    rest_api_id = aws_api_gateway_rest_api.CounterAPI.id
    resource_id = aws_api_gateway_resource.visits.id
    http_method = aws_api_gateway_method.options.http_method
    status_code = 200
    response_models = {
        "application/json" = "Empty"
    }
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Origin"  = true
    }
    depends_on = [
      aws_api_gateway_method.options
    ]
}


resource "aws_api_gateway_integration" "integrate1" {
    http_method             = aws_api_gateway_method.options.http_method
    resource_id             = aws_api_gateway_resource.visits.id
    rest_api_id             = aws_api_gateway_rest_api.CounterAPI.id
    type                    = "MOCK"
    request_templates = {
        "application/json" : "{\"statusCode: 200}"
    }
    passthrough_behavior = "WHEN_NO_MATCH"
    depends_on = [aws_api_gateway_method.options]

}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.CounterAPI.id
  resource_id = aws_api_gateway_resource.visits.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_method_response.options]
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.CounterAPI.id
  resource_id   = aws_api_gateway_resource.visits.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.CounterAPI.id
  resource_id             = aws_api_gateway_resource.visits.id
  http_method             = "POST"
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.visitorCount_lambda_function.invoke_arn
  depends_on              = [aws_api_gateway_method.post, aws_lambda_function.visitorCount_lambda_function]
}


resource "aws_api_gateway_deployment" "deployment1" {
  depends_on = [aws_api_gateway_integration.integrate1]   
  rest_api_id = aws_api_gateway_rest_api.CounterAPI.id
  stage_name = "prod"

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_api_gateway_stage" "prod" {
    deployment_id = aws_api_gateway_deployment.deployment1.id
    rest_api_id   = aws_api_gateway_rest_api.CounterAPI.id
    stage_name    = "prod"
}

resource "aws_lambda_permission" "apigw" {
    statement_id   = "AllowCounterAPIInvoke"
    action         = "lambda:InvokeFunction"
    function_name  = aws_lambda_function.visitorCount_lambda_function.arn
    principal      = "apigateway.amazonaws.com"
}






output "invoke_arn" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}"}
output "stage_name" {value = "${aws_api_gateway_stage.prod.stage_name}"}
output "path_part" {value = "${aws_api_gateway_resource.visits.path_part}"}
output "complete_unvoke_url" {value = "${aws_api_gateway_deployment.deployment1.invoke_url}${aws_api_gateway_stage.prod.stage_name}/${aws_api_gateway_resource.visits.path_part}"}



