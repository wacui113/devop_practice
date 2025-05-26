
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = terraform.workspace 
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = terraform.workspace
  }
}


resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true 

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = terraform.workspace
    Tier        = "Public"
  }
}


resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = terraform.workspace
    Tier        = "Private"
  }
}



resource "aws_eip" "nat_eip" {
  count = length(var.public_subnet_cidrs) 
  domain   = "vpc"
  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index + 1}"
    Environment = terraform.workspace
  }
}

resource "aws_nat_gateway" "nat" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id 

  tags = {
    Name        = "${var.project_name}-nat-gw-${count.index + 1}"
    Environment = terraform.workspace
  }
  depends_on = [aws_internet_gateway.gw]
}



resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index % length(aws_nat_gateway.nat)].id 
  }

  tags = {
    Name        = "${var.project_name}-private-rt-${count.index + 1}"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}




variable "my_ip_for_ssh" {
  description = "Your IP address for SSH access."
  type        = string
  
}

resource "aws_security_group" "allow_ssh" {
  name        = "${var.project_name}-allow-ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from My IP"
    from_port   = 22
    to_port     = 22
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
    Name        = "${var.project_name}-allow-ssh-sg"
    Environment = terraform.workspace
  }
}


resource "aws_security_group" "allow_web_traffic" {
  name        = "${var.project_name}-allow-web"
  description = "Allow HTTP/HTTPS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-allow-web-sg"
    Environment = terraform.workspace
  }
}



locals {
  docker_images = [
    "go-coffeeshop-web",
    "go-coffeeshop-proxy",
    "go-coffeeshop-barista",
    "go-coffeeshop-kitchen",
    "go-coffeeshop-counter",
    "go-coffeeshop-product"
    
    
  ]
}

resource "aws_ecr_repository" "app_images" {
  count = length(local.docker_images)
  name  = "${var.project_name}-${local.docker_images[count.index]}" 

  image_tag_mutability = "MUTABLE" 

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-${local.docker_images[count.index]}"
    Environment = "shared" 
  }
}


output "ecr_repository_urls" {
  description = "ECR Repository URLs"
  value       = { for repo in aws_ecr_repository.app_images : repo.name => repo.repository_url }
}
