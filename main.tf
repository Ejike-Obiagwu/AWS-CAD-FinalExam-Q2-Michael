provider "aws" {
  region = var.region
}

# S3 Bucket
resource "aws_s3_bucket" "cadexam_bucket" {
  bucket = var.bucket_name
}

# IAM Role 
resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"
  assume_role_policy = jsonencode({

    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      },
    ]
  })
}

# IAM Policy
resource "aws_iam_policy" "s3_full_access_policy" {
  name        = "s3-full-access-policy"
  description = "Provides full access to S3 buckets"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "s3:*",
        "Resource" : "*"
      },
    ]
  })
}
# Attach IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_full_access_policy.arn
}

resource "aws_vpc" "cadexamVPC" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "MichaelExamVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cadexamVPC.id

  tags = {
    Name = "MikeProjectigw"
  }
}

resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.cadexamVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRT"
  }
}

resource "aws_subnet" "project_public_subnet1" {
  vpc_id                  = aws_vpc.cadexamVPC.id
  cidr_block              = var.subnet1_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az1

  tags = {
    Name = "MichaelexamSubnet1"
  }
}

resource "aws_subnet" "project_public_subnet2" {
  vpc_id                  = aws_vpc.cadexamVPC.id
  cidr_block              = var.subnet2_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.az2

  tags = {
    Name = "MichaelexamSubnet2"
  }
}

resource "aws_route_table_association" "public_subnet_association1" {
  subnet_id      = aws_subnet.project_public_subnet1.id
  route_table_id = aws_route_table.publicRT.id
}

resource "aws_route_table_association" "public_subnet_association2" {
  subnet_id      = aws_subnet.project_public_subnet2.id
  route_table_id = aws_route_table.publicRT.id
}

resource "aws_instance" "app_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.project_public_subnet1.id

  tags = {
    Nmae = "MichaelTerraform_EC2"
  }
}


# Security Group for RDS
resource "aws_security_group" "RDS_SG" {
  vpc_id = aws_vpc.cadexamVPC.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Michael_RDS_SG"
  }
}

# Security Group for EC2
resource "aws_security_group" "EC2_SG" {
  vpc_id = aws_vpc.cadexamVPC.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Michael_EC2_SG"
  }
}

resource "aws_db_instance" "default" {
  allocated_storage           = 10
  db_name                     = "mydb"
  engine                      = "mysql"
  engine_version              = "5.7"
  instance_class              = "db.t3.micro"
  manage_master_user_password = true
  username                    = "admin"
  parameter_group_name        = "default.mysql5.7"
  skip_final_snapshot         = true
}

# KMS Key
resource "aws_kms_key" "example_kms" {
  description             = "KMS key for example"
  deletion_window_in_days = 10
}

# ALB
resource "aws_lb" "my_alb" {
  name                       = "my-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.EC2_SG.id]
  subnets                    = [aws_subnet.project_public_subnet1.id, aws_subnet.project_public_subnet2.id]
  enable_deletion_protection = false
}


resource "aws_autoscaling_group" "my_asg" {
  name                      = "my-asg"
  launch_configuration      = aws_launch_configuration.my_launch_config.name
  min_size                  = 2
  max_size                  = 5
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.project_public_subnet1.id, aws_subnet.project_public_subnet2.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300

}

resource "aws_launch_configuration" "my_launch_config" {
  name            = "my-launch-config"
  image_id        = var.ami_id
  instance_type   = var.instance_type
  security_groups = [aws_security_group.EC2_SG.id]

}

# Glue Job
resource "aws_glue_job" "cadexam_glue_job" {
  name     = var.glue_job_name
  role_arn = aws_iam_role.ec2_role.arn
  command {
    script_location = var.glue_script_location
    name            = "glueetl"
  }
  default_arguments = {
    "--job-language" = "python"
    "--TempDir"      = "s3://${aws_s3_bucket.cadexam_bucket.bucket}/temp/"
  }
  glue_version = "2.0"
  max_capacity = 2.0
}
