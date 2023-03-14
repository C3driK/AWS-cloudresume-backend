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
                {
      "Sid": "",
      "Action": "dynamodb:*",
      "Effect": "Allow",
      "Resource": "*"
    },
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
    source_code_hash = filebase64sha256("${path.module}/python/visitorCount.zip")
    depends_on = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}

output "terraform_aws_role_output" {
    value = aws_iam_role.lambda_role.name
}
output "terraform_aws_role_arn_output" {
    value = aws_iam_role.lambda_role.arn
}