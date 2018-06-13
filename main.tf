provider "aws" {
  region = "us-west-2"
  version = "~> 1.22.0"
}

provider "ignition" {
  version = "~> 1.0.1"
}

variable "ssh_key" {}

resource "aws_security_group" "not_secure"  {
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}


data "ignition_systemd_unit" "docker_dropin" {
  name = "docker.service"
  dropin = [
    {
      name = "10-opts.conf"
      content = "[Service]\nEnvironment=\"DOCKER_OPTS='--insecure-registry=0.0.0.0/0' '--log-driver=journald'\""
    }
  ]
}

data "ignition_config" "server" {
  systemd = [
    "${data.ignition_systemd_unit.docker_dropin.id}",
  ]
}

#####################################
########### Stager Server ###########
#####################################

## a server to use to stage images into the registry without suffering
## bandwidth restrictions from laptop --> aws
resource "aws_instance" "stager" {
  ## 1745.6.0 hvm
  ami = "ami-401f5e38"
  instance_type = "m4.large"
  key_name = "${var.ssh_key}"
  security_groups = ["${aws_security_group.not_secure.name}"]
  user_data = "${data.ignition_config.server.rendered}"
}

##############################################
########### Test Server 1745.6.0 #############
##############################################

resource "aws_instance" "broken_server" {
  ## 1745.6.0 hvm
  ami = "ami-401f5e38"

  ## not ebs optimized
  instance_type = "m3.large"
  key_name = "${var.ssh_key}"
  security_groups = ["${aws_security_group.not_secure.name}"]
  user_data = "${data.ignition_config.server.rendered}"
}

##############################################
########### Test Server 1745.5.0 #############
##############################################

resource "aws_instance" "working_server" {
  ## 1745.5.0 hvm
  ami = "ami-4296ec3a"

  ## not ebs optimized
  instance_type = "m3.large"
  key_name = "${var.ssh_key}"
  security_groups = ["${aws_security_group.not_secure.name}"]
  user_data = "${data.ignition_config.server.rendered}"
}

#####################################
########## Test Registry ############
#####################################

resource "aws_s3_bucket" "registry" {
  bucket_prefix = "testregistry"
  acl = "private"
  force_destroy = true
}

resource "aws_iam_instance_profile" "registry" {
    name = "testregistry"
    role = "${aws_iam_role.registry.name}"
    depends_on = [ "aws_iam_role.registry" ]
}
data "aws_caller_identity" "current" {}
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "registry" {
    name = "testregistry"
    assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}
resource "aws_iam_role_policy" "registry" {
  name_prefix = "s3"
  role = "${aws_iam_role.registry.id}"
  policy = "${data.aws_iam_policy_document.registry.json}"
}
data "aws_iam_policy_document" "registry" {
  policy_id = "s3"
  statement {
    sid = "s1"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "${aws_s3_bucket.registry.arn}",
      "${aws_s3_bucket.registry.arn}/*"
    ]
  }
}

resource "aws_instance" "registry" {
  ami = "ami-401f5e38"
  instance_type = "m4.large"
  key_name = "${var.ssh_key}"
  security_groups = ["${aws_security_group.not_secure.name}"]
  iam_instance_profile = "${aws_iam_instance_profile.registry.name}"
  user_data = "${data.ignition_config.registry.rendered}"
}

data "template_file" "registry_service" {
  template = "${file("./resources/registry.service")}"

  vars {
    registry_bucket = "${aws_s3_bucket.registry.id}"
  }
}

data "ignition_systemd_unit" "registry_service" {
  name = "registry.service"
  content = "${data.template_file.registry_service.rendered}"
}

data "ignition_config" "registry" {
  systemd = [
    "${data.ignition_systemd_unit.registry_service.id}",
  ]
}

output "staging_server_ip" {
  value = "${aws_instance.stager.public_ip}"
}
output "server_1745_6_0_broken_ip" {
  value = "${aws_instance.broken_server.public_ip}"
}
output "server_1745_5_0_working_ip" {
  value = "${aws_instance.working_server.public_ip}"
}
output "registry_ip" {
  value = "${aws_instance.registry.public_ip}"
}
