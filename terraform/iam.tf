data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ch" {
  name               = "${var.project}-ch"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ch.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw" {
  role       = aws_iam_role.ch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Lets instances discover each other's tags / IPs if needed
resource "aws_iam_role_policy" "ec2_read" {
  name = "ec2-describe"
  role = aws_iam_role.ch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags", "ec2:DescribeVolumes"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ch" {
  name = "${var.project}-ch"
  role = aws_iam_role.ch.name
}
