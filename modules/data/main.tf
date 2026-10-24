# One table holds every user's tasks.
# Partition key = userId (the Cognito "sub"), sort key = taskId.
# A query on userId returns only that user's items, so users can never see each other's data.
resource "aws_dynamodb_table" "tasks" {
  name         = "${var.name}-tasks"
  billing_mode = "PAY_PER_REQUEST" # serverless: no capacity to manage, pay per request
  hash_key     = "userId"
  range_key    = "taskId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "taskId"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${var.name}-tasks" }
}
