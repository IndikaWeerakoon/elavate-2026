resource "aws_dynamodb_table" "source" {
  name             = "${var.name_prefix}-source"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "destination" {
  name         = "${var.name_prefix}-destination"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cloudRecordId"

  attribute {
    name = "cloudRecordId"
    type = "S"
  }
}
