
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
       bucket = "cambiumspininfra"
       region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {

  tag_name = "aws-demo-infra"
}


resource "aws_vpc" "cambium-nw-vpc" {
  cidr_block = "10.0.0.0/23"
  tags = {
    Name = "${local.tag_name}vpc"
  }
}


resource "aws_subnet" "cambium-nw-subnet" {

  for_each = {

    private-sub-1 = ["10.0.0.0/27", "us-east-1a"]
    private-sub-2 = ["10.0.0.32/27", "us-east-1b"]
    public-sub-1  = ["10.0.0.64/27", "us-east-1a"]
    public-sub-2  = ["10.0.0.96/27", "us-east-1b"]

  }

  vpc_id            = aws_vpc.cambium-nw-vpc.id
  cidr_block        = each.value[0]
  availability_zone = each.value[1]

  tags = {
    Name = "${local.tag_name}${each.key}"
  }

}

resource "aws_internet_gateway" "cambium-nw-aws-igw" {
  vpc_id = aws_vpc.cambium-nw-vpc.id
  tags = {
    Name = "${local.tag_name}igw"
  }
}

resource "aws_eip" "cambium-nw-eip-nat" {
  tags = {
    Name = "${local.tag_name}eip-nat"
  }
}

resource "aws_nat_gateway" "cambium-nw-nat" {

  allocation_id = aws_eip.cambium-nw-eip-nat.id
  subnet_id     = aws_subnet.cambium-nw-subnet["public-sub-1"].id
  tags = {
    Name = "${local.tag_name}nat"
  }
}

resource "aws_route_table" "cambium-nw-private-rt" {
  vpc_id = aws_vpc.cambium-nw-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.cambium-nw-nat.id
  }
  tags = {
    Name = "${local.tag_name}private-rt"
  }
}

resource "aws_route_table" "cambium-nw-public-rt" {
  vpc_id = aws_vpc.cambium-nw-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cambium-nw-aws-igw.id
  }
  tags = {
    Name = "${local.tag_name}public-rt"

  }
}


resource "aws_route_table_association" "cambium-nw-routetable-associate" {

  for_each = {

    private_subnet_1 = [aws_route_table.cambium-nw-private-rt.id, aws_subnet.cambium-nw-subnet["private-sub-1"].id]
    private_subnet_2 = [aws_route_table.cambium-nw-private-rt.id, aws_subnet.cambium-nw-subnet["private-sub-2"].id]
    public_subnet_1  = [aws_route_table.cambium-nw-public-rt.id, aws_subnet.cambium-nw-subnet["public-sub-1"].id]
    public_subnet_2  = [aws_route_table.cambium-nw-public-rt.id, aws_subnet.cambium-nw-subnet["public-sub-2"].id]

  }

  route_table_id = each.value[0]
  subnet_id      = each.value[1]
}

locals {
  ingress_rules = [
    {
      port        = 22
      description = "Allow SSH within VPC"

    },
    {
      port        = 3389
      description = "Allow RDP within VPC"

    },

    {
      port = 5000
      description = "Allow FLASK port within VPC"

    }

  ]
}


resource "aws_security_group" "cambium-nw-allow-access-inside" {

  name        = "Allow SSH/RDP/FLASK VPC within VPC"
  description = "Allow SSH/RDP/FLASK VPC within VPC"

  vpc_id = "${aws_vpc.cambium-nw-vpc.id}"

  dynamic "ingress" {
    for_each = local.ingress_rules
    content {

      description = ingress.value.description
      to_port     = ingress.value.port
      from_port   = ingress.value.port
      cidr_blocks = [aws_vpc.cambium-nw-vpc.cidr_block]
      protocol    = "tcp"
    }
  }

  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_name}security-group"
  }
}

locals {
  ingress_rules_outside = [
       {
      port = 80
      description = "Allow HTTP within VPC"
    },

    {
      port = 443
      description = "Allow HTTPS port accessible over internet "
    }
  ]
}


resource "aws_security_group" "cambium-nw-allow-access-outside" {

  name        = "Allow HTTP/HTTPS from everywhere"
  description = "Allow HTTP/HTTPS from everywhere"

  vpc_id = "${aws_vpc.cambium-nw-vpc.id}"

  dynamic "ingress" {
    for_each = local.ingress_rules_outside
    content {

      description = ingress.value.description
      to_port     = ingress.value.port
      from_port   = ingress.value.port
      cidr_blocks = ["0.0.0.0/0"]
      protocol    = "tcp"
    }
  }

  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_name}security-group-access-outside"
  }
}

// create target group

resource "aws_lb_target_group" "cambium-nw-tgw" {
  name     = "cambium-nw-tgw-lb-tgw"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.cambium-nw-vpc.id

}

resource "aws_lb" "cambium-nw-alb" {
  name               = "cambium-nw-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.cambium-nw-allow-access-outside.id]
  enable_deletion_protection = true
  subnets = [ aws_subnet.cambium-nw-subnet["public-sub-1"].id , aws_subnet.cambium-nw-subnet["public-sub-2"].id ]

  tags = {
    Name = "${local.tag_name}application-load-balancer-outside"
  }
}

resource "aws_lb_listener" "cambium-nw-alb_listener" {
  load_balancer_arn = aws_lb.cambium-nw-alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cambium-nw-tgw.arn
  }
    tags = {
    Name = "${local.tag_name}hello-world-flask-app-tgw"
  }
}

resource "aws_instance" "cambium-nw-helloworld-flask-app" {

    ami = "ami-087c17d1fe0178315"
    instance_type = "t2.large"
    security_groups = [ aws_security_group.cambium-nw-allow-access-inside.id ]
    subnet_id = aws_subnet.cambium-nw-subnet["private-sub-1"].id
    depends_on = [ aws_nat_gateway.cambium-nw-nat]
    user_data = <<-EOF
        #!/bin/bash
        yum install docker git -y
        systemctl start docker
        systemctl enable docker
        git clone https://github.com/Rohitkuru/cambium_networks.git
        cd cambium_networks
        docker build -t flask_app:latest .
        docker run -d -p 5000:5000 flask_app:latest
        EOF
  tags = {
    Name = "${local.tag_name}hello-world-flask-web-app-server"
  }

}

resource "aws_lb_target_group_attachment" "cambium-nw-target-group-attachment" {
  target_group_arn = aws_lb_target_group.cambium-nw-tgw.arn
  target_id = aws_instance.cambium-nw-helloworld-flask-app.id
  port             = 5000
}
