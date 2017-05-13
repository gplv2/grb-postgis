# See https://cloud.google.com/compute/docs/load-balancing/network/example

# Set up AWS access to environment
provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "${var.aws_region}"
}

provider "google" {
  region = "${var.region}"
  project = "${var.project_name}"
  credentials = "${file("${var.credentials_file_path}")}"
}

# Set up db groups
resource "google_compute_instance_group" "db" {
  name        = "terraform-db"
  description = "Terraform DB instance group"
  zone = "${var.region_zone}"
  instances = ["${google_compute_instance.db.*.self_link}"]
}

# Disk image depends on region and zone
resource "google_compute_instance" "db" {
  count = 1

  name = "tf-db-${count.index}"
  machine_type = "n1-highmem-4"
  zone = "${var.region_zone}"
 
  scheduling {
    preemptible          = false
    automatic_restart    = true
    on_host_maintenance  = "MIGRATE"
  }

  tags = ["db-node"]
  disk {
    image = "ubuntu-os-cloud/ubuntu-1604-xenial-v20160907a"
    size = 200
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral
    }
  }

  metadata {
    ssh-keys = "root:${file("${var.public_key_path}")}"
  }

  provisioner "file" {
    source = "${var.install_script_src_path}"
    destination = "${var.install_script_dest_path}"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# Copies the bitbucket keys over
  provisioner "file" {
    source = "keys/"
    destination = "/root/.ssh/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }


# installs the config
  provisioner "file" {
    source = "scripts/ssh_config"
    destination = "/root/.ssh/config"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# prepare TF corner
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
    inline = [
      "mkdir -p /tmp/terraform"
    ]
  }

  provisioner "file" {
    source = "terraform.tfvars"
    destination = "/tmp/terraform/terraform.tfvars"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# Install all terraform runtime stuff
  provisioner "file" {
    source = "${var.credentials_file_path}"
    destination = "/tmp/terraform/terraform-${var.project_name}.json"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

  # all the shell files in /tmp
  provisioner "file" {
    source = "helpers/"
    destination = "/tmp/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# Create an empty file under etc to indicate the project this server belongs to
# Thought about doing this differently in a few ways since this is the only missing
# Piece of information in order to configure the python script that can call it all.

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
    inline = [
      "mkdir -p /tmp/skeys",
      "sudo echo ${var.project_name} > /etc/myproject",
      "sudo chmod +r /etc/myproject"
    ]
  }

# sftp keys 
# Copy all accepted public keys over
  provisioner "file" {
    source = "sftpkeys/"
    destination = "/tmp/skeys/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# Copy config artifacts over to use later
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
    inline = [
      "mkdir -p /tmp/configs"
    ]
  }

  provisioner "file" {
    source = "configs/"
    destination = "/tmp/configs/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

# Copy cron snippets to nodes
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
    inline = [
      "mkdir -p /tmp/crons"
    ]
  }

  provisioner "file" {
    source = "crons/"
    destination = "/tmp/crons/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

  # all the shell files in /tmp
  provisioner "file" {
    source = "helpers/"
    destination = "/tmp/"
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "root"
      private_key = "${file("${var.private_key_path}")}"
      agent = false
    }
    inline = [
      "chmod +x ${var.install_script_dest_path}",
      "sudo ${var.install_script_dest_path} ${count.index}"
    ]
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }
}

resource "google_compute_firewall" "default" {
  name = "tf-www-firewall"
  network = "default"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["www-node"]
}

# Setup storage of terraform statefile in s3.
# You should change stuff here if you are working on a different environment,
# especially if you are working with two separate environments in one region.
data "terraform_remote_state" "ops" {
  backend = "s3"
  config {
    bucket     = "my-tf-states"
    key        = "${var.project_name}/terraform.tfstate"
    region     = "${var.aws_region}"
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
  }
}
