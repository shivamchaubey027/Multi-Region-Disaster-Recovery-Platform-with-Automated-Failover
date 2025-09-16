data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ip_ranges" "ec2_instance_connect" {
  regions  = ["eu-north-1"]
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
  region = "eu-north-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.128.0/17"
  tags = {
    Name= "dr-passive-vpc"
  }
}

#Building Subnets

resource "aws_subnet" "public_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.128.0/24"
    availability_zone = "eu-north-1a"
    map_public_ip_on_launch = true
    tags = {
    Name= "dr-public-subnet-a"
  }
  
}

resource "aws_subnet" "private_subnet_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.129.0/24"
    availability_zone = "eu-north-1a"
    
    
    tags = {
    Name= "dr-private-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.130.0/24"
    availability_zone = "eu-north-1b"
    map_public_ip_on_launch = true
    tags = {
    Name= "dr-public-subnet-b"
  }
  
}

resource "aws_subnet" "private_subnet_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.131.0/24"
    availability_zone = "eu-north-1b"

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
              echo "<h1>Hello from Terraform in eu-north-1a</h1>" > /var/www/html/index.html
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


output "Outputs" {
    value = aws_instance.public_ec2.public_ip
}

resource "aws_route" "to_peer" {
  route_table_id = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/17"
  vpc_peering_connection_id = "pcx-0b78e4b15b72abf60"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "dr-replica-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  tags = {
    Name="DR Replica DB Subnet Group"
  }
}

resource "aws_security_group" "db_sg" {
  name = "dr-replica-db-sg"
  description = "ALlow traffic from primary region vpc"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from the us-east-1"
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/17"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name="DR Replica DB security Group"
  }

}


resource "aws_db_instance" "db_replica" {
  identifier = "dr-db-replica"
  instance_class = "db.t3.micro"
  skip_final_snapshot = true

  replicate_source_db = "arn:aws:rds:us-east-1:145023127201:db:dr-main-db"

  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  tags = {
    Name="DR Replica Database"
  }
}