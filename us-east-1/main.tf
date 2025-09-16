data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ip_ranges" "ec2_instance_connect" {
  regions  = ["us-east-1"]
  services = ["ec2_instance_connect"]
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/17"
  tags = {
    Name= "dr-primary-vpc"
  }
}

#Building Subnets

resource "aws_subnet" "public_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
    tags = {
    Name= "dr-public-subnet-a"
  }
  
}

resource "aws_subnet" "private_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    
    
    tags = {
    Name= "dr-private-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    tags = {
    Name= "dr-public-subnet-b"
  }
  
}

resource "aws_subnet" "private_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.3.0/24"
    availability_zone = "us-east-1b"

    tags = {
      Name="dr-private-subnet-b"
    }
}


    #Networking

resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id
    tags = {
    Name="Internet Gateway" 
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    tags = {
    Name = "dr-public-rtb"
    }
}

resource "aws_route" "public_internet_route" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id

}

resource "aws_route_table_association" "public_a" {
  subnet_id = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public.id
}

#Security Groups

resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.main.id

  ingress{
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from EC2 Instance Connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = data.aws_ip_ranges.ec2_instance_connect.cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name="Public Security"
  }
}

resource "aws_instance" "public_ec2" {
  ami = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  subnet_id = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [ aws_security_group.public_sg.id ]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Terraform in us-east-1a</h1>" > /var/www/html/index.html
              EOF
  tags = {
    Name="public_ec2"
  }
}



resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name="dr-private-rtb"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private.id
}



provider "aws" {
  alias = "peer_region"
  region = "eu-north-1"
}

resource "aws_vpc_peering_connection" "peer" {
    vpc_id = "vpc-0b15fdd7b4d931c59"

    peer_vpc_id = "vpc-0fdb047067fc5d078"
    peer_region = "eu-north-1"
    
    auto_accept = false

    tags = {
      Name="dr-peering-us-east-1-to-eu-north-1"
    }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider = aws.peer_region
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  auto_accept= true

  tags={
    Name= "dr-peering-us-east-1-to-eu-north-1"
  }

}

resource "aws_route" "to_peer" {
  route_table_id = aws_route_table.private.id
  destination_cidr_block = "10.0.128.0/17"
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}




resource "aws_db_subnet_group" "db_subnet_group" {
  subnet_ids = [ aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id ]
  tags = {
    Name="The subnets in which we can have the database"
  }
}

resource "aws_security_group" "db_sg" {
  name = "dr-db-sg"
  description = "Allow traffic to db only from the webserver"
  vpc_id = aws_vpc.main.id
  ingress {
    description     = "PostgreSQL from the public security group"
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name="DR DB Security Group"
  }
}


resource "aws_db_instance" "main_db" {
  identifier = "dr-main-db"
  engine = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  storage_type = "gp2"

  backup_retention_period = 7
  apply_immediately = true
  db_name = "appdb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  multi_az = true

  skip_final_snapshot = true

  tags = {
    Name="DR Primary Database"
  }
}



output "Outputs" {
  value = aws_instance.public_ec2.public_ip
}

output "vpc_peering_connection_id" {
  description = "The id of the VPC Peering Connection"
  value = aws_vpc_peering_connection.peer.id
}

output "primary_db_arn" {
  description = "The ARN of the primary RDS database"
  value = aws_db_instance.main_db.arn
  
}


resource "aws_cloudwatch_metric_alarm" "unhealthy_host" {
  alarm_name = "unhealthy-primary-web-server"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "StatusCheckFailed"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Maximum"
  threshold = "1"
  alarm_actions = [aws_sns_topic.failover_topic.arn]
  alarm_description = "This alarm fires when the primary EC2 instance fails its status check"

  dimensions = {
    InstanceId = aws_instance.public_ec2.id
  }
}

resource "aws_sns_topic" "failover_topic" {
  name = "failover-alerts"
  tags = {
    Name=" DR Failover Topic"
  }
}

