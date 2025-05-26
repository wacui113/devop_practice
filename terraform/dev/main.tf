
variable "dev_instance_type" {
  description = "EC2 instance type for Dev environment."
  type        = string
  default     = "t2.micro" 
}

variable "dev_ami_id" {
  description = "AMI ID for Dev EC2 instance."
  type        = string
  
  
  
}

variable "dev_key_name" {
  description = "Name of the EC2 Key Pair for SSH access to Dev instance."
  type        = string
  
}








data "aws_vpc" "main" {
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = terraform.workspace 
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["Public"]
  }
  tags = {
    Environment = terraform.workspace
  }
}


resource "aws_security_group" "dev_ec2_sg" {
  name        = "${var.project_name}-dev-ec2-sg"
  description = "Allow traffic for Dev EC2 instance"
  vpc_id      = data.aws_vpc.main.id

  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_for_ssh] 
  }

  
  
  
  ingress {
    description = "Web App HTTP"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
   
  ingress {
    description = "Proxy App"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "RabbitMQ Management"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_for_ssh] 
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-dev-ec2-sg"
    Environment = terraform.workspace
  }
}


resource "aws_iam_role" "dev_ec2_role" {
  name = "${var.project_name}-dev-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.project_name}-dev-ec2-role"
    Environment = terraform.workspace
  }
}


resource "aws_iam_role_policy_attachment" "dev_ec2_ecr_readonly" {
  role       = aws_iam_role.dev_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "dev_ec2_cloudwatch_agent" {
   role       = aws_iam_role.dev_ec2_role.name
   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


resource "aws_iam_instance_profile" "dev_ec2_instance_profile" {
  name = "${var.project_name}-dev-ec2-instance-profile"
  role = aws_iam_role.dev_ec2_role.name
   tags = {
    Name        = "${var.project_name}-dev-ec2-instance-profile"
    Environment = terraform.workspace
  }
}



resource "aws_instance" "dev_server" {
  ami           = var.dev_ami_id          
  instance_type = var.dev_instance_type
  key_name      = var.dev_key_name        
  subnet_id     = data.aws_subnets.public.ids[0] 
  vpc_security_group_ids = [aws_security_group.dev_ec2_sg.id, aws_security_group.allow_ssh.id] 
  iam_instance_profile = aws_iam_instance_profile.dev_ec2_instance_profile.name

  
  user_data = <<-EOF
              
              
              sudo yum update -y
              sudo amazon-linux-extras install docker -y
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -a -G docker ec2-user

              
              sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose

              
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              rm -rf aws awscliv2.zip

              
              sudo yum install git -y

              
              sudo yum install amazon-cloudwatch-agent -y
              
              
              EOF

  tags = {
    Name        = "${var.project_name}-dev-server"
    Environment = terraform.workspace
  }
}


output "dev_server_public_ip" {
  description = "Public IP address of the Dev EC2 instance."
  value       = aws_instance.dev_server.public_ip
}

output "dev_server_public_dns" {
  description = "Public DNS of the Dev EC2 instance."
  value       = aws_instance.dev_server.public_dns
}
