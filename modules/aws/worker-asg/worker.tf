data "aws_ami" "coreos_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CoreOS-${var.tectonic_cl_channel}-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-id"
    values = ["595879546273"]
  }
}

resource "aws_launch_configuration" "worker_conf" {
  instance_type        = "${var.tectonic_aws_worker_ec2_type}"
  image_id             = "${data.aws_ami.coreos_ami.image_id}"
  name_prefix          = "${var.tectonic_cluster_name}-worker-"
  key_name             = "${var.ssh_key}"
  security_groups      = ["${concat(list(aws_security_group.worker_sec_group.id), var.extra_sg_ids)}"]
  iam_instance_profile = "${aws_iam_instance_profile.worker_profile.arn}"

  user_data = "${ignition_config.worker.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "workers" {
  name                 = "${var.tectonic_cluster_name}-worker"
  desired_capacity     = "${var.tectonic_worker_count}"
  max_size             = "${var.tectonic_worker_count * 3}"
  min_size             = "${var.tectonic_worker_count}"
  launch_configuration = "${aws_launch_configuration.worker_conf.id}"
  vpc_zone_identifier  = ["${var.worker_subnet_ids}"]

  tag {
    key                 = "Name"
    value               = "${var.tectonic_cluster_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "KubernetesCluster"
    value               = "${var.tectonic_cluster_name}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "worker_profile" {
  name  = "${var.tectonic_cluster_name}-worker-profile"
  roles = ["${aws_iam_role.worker_role.name}"]
}

resource "aws_iam_role" "worker_role" {
  name = "${var.tectonic_cluster_name}-worker-role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "worker_policy" {
  name = "${var.tectonic_cluster_name}_worker_policy"
  role = "${aws_iam_role.worker_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:*",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": "elasticloadbalancing:*",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:BatchGetImage"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}