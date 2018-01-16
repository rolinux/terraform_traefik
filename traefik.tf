variable "region" {}
variable "vpc_name" {}
variable "vpc_cidr" {}
variable "subnet_public_cidr" {}
variable "subnet_private_cidr" {}
variable "current_ip" {}

provider "aws" {
  region     = "${var.region}"
}

resource "aws_vpc" "custom" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  tags {
    Name = "${var.vpc_name}"
  }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.custom.id}"
  cidr_block = "${var.subnet_public_cidr}"
  availability_zone = "${var.region}a"
  map_public_ip_on_launch = true

  tags {
    Name = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id = "${aws_vpc.custom.id}"
  cidr_block = "${var.subnet_private_cidr}"
  availability_zone = "${var.region}a"
  map_public_ip_on_launch = false

  tags {
    Name = "private"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.custom.id}"
}

resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "gw" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.public.id}"

  depends_on = ["aws_internet_gateway.gw"]
}

resource "aws_route_table" "private" {
  vpc_id                 = "${aws_vpc.custom.id}"
}

# Attach a route to 0/0 to the _private_ route table going to the NAT gateway.
resource "aws_route" "private" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.gw.id}"
}

# Associate the _private_ route table with the _private_ network.
resource "aws_route_table_association" "private" {
  subnet_id              = "${aws_subnet.private.id}"
  route_table_id         = "${aws_route_table.private.id}"
}

resource "aws_route_table" "public" {
  vpc_id                 = "${aws_vpc.custom.id}"
}

resource "aws_route" "public" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id         = "${aws_internet_gateway.gw.id}"
}

# Associate the _private_ route table with the _private_ network.
resource "aws_route_table_association" "public" {
  subnet_id              = "${aws_subnet.public.id}"
  route_table_id         = "${aws_route_table.public.id}"
}

resource "aws_security_group" "public_sg" {
  name        = "public_sg"
  description = "Allow ssh traffic from current BT IP and all out"
  vpc_id      = "${aws_vpc.custom.id}"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.current_ip}/32"]
  }
  egress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags {
    Name = "public_sg"
  }
}

resource "aws_spot_instance_request" "bastion" {
  ami           = "ami-2452275e"
  subnet_id     = "${aws_subnet.public.id}"
  spot_price    = "0.005"
  instance_type = "t2.micro"
  key_name = "radu@hc"
  security_groups = [
    "${aws_security_group.public_sg.id}"
  ]

  tags {
    Name = "bastion"
  }
}

resource "aws_security_group" "bastion_to_private" {
  name        = "bastion_to_private"
  description = "Allow ssh traffic from bastion to private"
  vpc_id      = "${aws_vpc.custom.id}"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["${aws_security_group.public_sg.id}"]
  }
  egress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags {
    Name = "bastion_to_private"
  }
}

resource "aws_spot_instance_request" "wrk" {
  ami           = "ami-2452275e"
  subnet_id     = "${aws_subnet.private.id}"
  spot_price    = "0.005"
  instance_type = "t2.micro"
  key_name = "radu@bastion"
  security_groups = [
    "${aws_security_group.bastion_to_private.id}"
  ]

  tags {
    Name = "wrk"
  }
}
