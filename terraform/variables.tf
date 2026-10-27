variable "aws_profile" {
  description = "AWS CLI profile used to run terraform"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the public ssh key installed on the EC2 host"
  type        = string
}
