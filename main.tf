# See https://cloud.google.com/compute/docs/load-balancing/network/example

provider "google" {
  region = var.region
  project = var.project_name
  credentials = file("${var.credentials_file_path}")
}

# Set up db groups
resource "google_compute_instance_group" "db" {
  name        = "terraform-db"
  description = "Terraform DB instance group"
  zone = var.region_zone
  instances = ["${google_compute_instance.db.0.self_link}"]
  #instances  = "${join(" ", ${google_compute_instance.db.*.self_link})}"
  #instances   = join(" ", "${google_compute_instance.db.*.self_link}")

}

#resource "google_compute_address" "static" {
  #name = "ipv4-address"
#}

## Disk image depends on region and zone
resource "google_compute_disk" "data1" {
    count = 1
    name        = "data-disk1"
    type        = "pd-ssd"
    zone = var.region_zone
    #auto_delete = true   deprecated ?
    #scratch     = true
    size        = 100
}

resource "google_compute_disk" "data2" {
    count = 1
    name        = "data-disk2"
    type        = "pd-ssd"
    zone = var.region_zone
    #auto_delete = true   deprecated ?
    #scratch     = true
    size        = 100
}

# Disk image depends on region and zone
resource "google_compute_instance" "db" {
  count = 1

  name = "grb-db-${count.index}"
  machine_type = "n1-highmem-8"
#   machine_type = "custom-6-15360"
  zone = var.region_zone

  scheduling {
    preemptible          = false
    automatic_restart    = true
    on_host_maintenance  = "MIGRATE"
  }

# "db-node", "www-node","http-server", "https-server"
  tags = ["db-node", "www-node"]

  boot_disk {
    initialize_params {
        image = "ubuntu-os-cloud/ubuntu-1804-bionic-v20211214"
        size = 100
    }
  }

    connection {
      # host = google_compute_instance.db.0.network_interface.0.network_ip
      host = google_compute_instance.db[count.index].network_interface.0.access_config.0.nat_ip
      type = "ssh"
      user = "root"
      private_key = file("${var.private_key_path}")
      agent = false
    }

   attached_disk {
     source      = google_compute_disk.data1[count.index].self_link
   }

   attached_disk {
     source      = google_compute_disk.data2[count.index].self_link
   }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral
    }
  }

  metadata = {
    ssh-keys = "root:${file("${var.public_key_path}")}"
  }

  provisioner "file" {
    source = var.install_script_src_path
    destination = var.install_script_dest_path
  }

# Copies the deployment keys over
  provisioner "file" {
    source = "keys/"
    destination = "/root/.ssh/"
  }


# installs helper script to set kernel shared segment size
  provisioner "file" {
    source = "scripts/shmsetup.sh"
    destination = "/usr/local/bin/shmsetup.sh"
  }

# installs google deprecated script to mounts disk without changing too much code (they removed it)
  provisioner "file" {
    source = "scripts/safe_format_and_mount.sh"
    destination = "/usr/local/bin/safe_format_and_mount.sh"
  }

# prepare TF corner
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/terraform",
      "mkdir -p /tmp/rcfiles"
    ]
  }

  provisioner "file" {
    source = "terraform.tfvars"
    destination = "/tmp/terraform/terraform.tfvars"
  }

# Install all terraform runtime stuff
  provisioner "file" {
    source = var.credentials_file_path
    destination = "/tmp/terraform/terraform-${var.project_name}.json"
  }

  # all the shell files in /tmp
  provisioner "file" {
    source = "helpers/"
    destination = "/tmp/"
  }

  # all the resource files in /tmp/rcfiles
  provisioner "file" {
    source = "rcfiles/"
    destination = "/tmp/rcfiles/"
  }

# Create an empty file under etc to indicate the project this server belongs to
# Thought about doing this differently in a few ways since this is the only missing
# Piece of information in order to configure the python script that can call it all.

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/skeys",
      "sudo echo ${var.project_name} > /etc/myproject",
      "sudo chmod +r /etc/myproject"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/configs"
    ]
  }

  provisioner "file" {
    source = "configs/"
    destination = "/tmp/configs/"
  }

# Copy cron snippets to nodes
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/crons"
    ]
  }

  provisioner "file" {
    source = "crons/"
    destination = "/tmp/crons/"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/safe_format_and_mount.sh",
      "chmod +x /tmp/mountformat.sh",
      "sudo /tmp/mountformat.sh",
      "chmod +x ${var.install_script_dest_path}",
      "chmod +x /usr/local/bin/shmsetup.sh",
      "sudo ${var.install_script_dest_path} ${count.index}"
    ]
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }
}

resource "google_compute_firewall" "default" {
  name = "grb-www-firewall"
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

# this is the S3 remote TF state location, it's meant to be used when you
# work in teams
#terraform {
#  backend "s3" {
#    bucket     = "my-tf-states"
#    key        = "api-project-37604919139/terraform.state"
#    region     = "eu-central-1"
#  }
#}
