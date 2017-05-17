#  What this script should do

 - install postgres/postgis
 - install toolsets
 - get the datafiles
 - crunch the data
 - build a postgis db
 - export the data

# assumptions
 - google cloud, might support others too in the future

# INSTALL TERRAFORM

Terraform must first be installed on your machine. Terraform is distributed as a binary package for all supported platforms and architecture. This page will not cover how to compile Terraform from source.

## Installing Terraform

Terraform must first be installed on your machine. Terraform is distributed as a binary package for all supported platforms and architecture. we will not cover how to compile Terraform from source.  To install Terraform, find the appropriate package for your system and download it. Terraform is packaged as a zip archive.

See [Installing Terraform](https://www.terraform.io/intro/getting-started/install.html) for the linux/mac procedures

After downloading Terraform, unzip the package into a directory where Terraform will be installed. The directory will contain a binary program terraform. The final step is to make sure the directory you installed Terraform to is on the PATH. .e.g `export PATH=$PATH:<terraform_bin_location_dir>`

## Preparing Terraform

We will cover google cloud specific.

### Terraform file layout

 - main.tf -- contains the definition of what we want to achieve
 - variables.tf -- contains the variables definition.
 - terraform.tfvars -- contains the values for variables.
 - output.tf -- contains the output that you want to see.

## Preparing Terraform

Terraform is easy to take in hand, the following subcommands do what you expect:

terraform plan -- Displays what would be executed
terraform apply -- Applies the changes
terraform destroy -- Wipes out what have been created

### Google cloud credentials

You can check google cloud information page concerning the zones and locations to deploy and match them in the tf files https://cloud.google.com/compute/docs/regions-zones/regions-zones.

### Download Authentication JSON File

[download your credentials from Google Cloud Console](https://www.terraform.io/docs/providers/google/#credentials); suggested path for downloaded file is `~/.gcloud/Terraform.json`.

Authenticating with Google Cloud services requires a JSON file which we call the account file.  This file is downloaded directly from the Google Developers Console. To make the process more straightforwarded, it is documented :

 - Log into the Google Developers Console and select a project.

 - The API Manager view should be selected, click on "Credentials" on the left, then "Create credentials", and finally "Service account key".

 - Select "Compute Engine default service account" in the "Service account" dropdown, and select "JSON" as the key type.

 - Clicking "Create" will download your credentials.

Save this file as `~/.gcloud/Terraform.json`

### Variables

variables.tf holds the definition of the elements that can be configured in your
deployment script.


## Google Cloud Architecture preparation

You will need to generate SSH keys as follows:

```sh
$ ssh-keygen -f ~/.ssh/gcloud_id_rsa
# press <Enter> when asked (twice) for a pass-phrase
```
Optionally update `variables.tf` to specify a default value for the `project_name` variable, and check other variables.

After you run `terraform apply` on this configuration, it will
automatically output the public IP address of the load balancer.
After your instance registers, the LB should respond with a simple header:

```html
<h1>Welcome to instance 0</h1>
```

The index may differ once you increase `count` of `google_compute_instance`
(i.e. provision more instances).

To run, configure your Google Cloud provider as described in

https://www.terraform.io/docs/providers/google/index.html

## Using Terraform

Run with a command like this (be aware, us region in this example )

### Planning

```
terraform apply \
	-var="region=us-central1" \
	-var="region_zone=us-central1-f" \
	-var="project_name=my-project-id-123" \
	-var="credentials_file_path=~/.gcloud/Terraform.json" \
	-var="public_key_path=~/.ssh/gcloud_id_rsa.pub" \
	-var="private_key_path=~/.ssh/gcloud_id_rsa"
```
----

### Deploying

First thing you need which is typically excluded from being checked in in git is the `terraform.tfvars` file.   Example content:

    region = "europe-west1"
    region_zone = "europe-west1-d"
    project_name = "my_google_projectnumber"
    credentials_file_path = "~/.gcloud/Terraform.json" 
    public_key_path = "~/.ssh/gcloud_id_rsa.pub"
    private_key_path = "~/.ssh/gcloud_id_rsa"

Create your version of the file for Google cloud (aka, create project etc). Adjust the values. Once you have all this stuff setup up, your google cloud project, a service account etc. you should be set to deploy safely.

# Example

## Terraform - Show the plan

See what is going to happen when you execute `terraform` exec:

    glenn@slicky:~/repos/terraform$ terraform plan

    Refreshing Terraform state in-memory prior to plan...
    The refreshed state will be used to calculate this plan, but
    will not be persisted to local or remote state storage.

    google_compute_http_health_check.sandbox_test: Refreshing state... (ID: grb-sandbox-basic-check)
    google_compute_firewall.sandbox-firewall: Refreshing state... (ID: grb-sandbox-firewall)
    google_compute_instance.sandbox: Refreshing state... (ID: grb-sandbox-0)
    google_compute_instance_group.sandbox: Refreshing state... (ID: terraform-sandbox)

    No changes. Infrastructure is up-to-date. This means that Terraform
    could not detect any differences between your configuration and
    the real physical resources that exist. As a result, Terraform
    doesn not need to do anything.

So we are good here.  In case something got tainted, you would see what is going to happen. (notice the red/green text colors)

## Terraform - Apply the plan

    glenn@slicky:~/repos/terraform$ terraform apply

Watch the magic.  The provisioner script installation is set in bash debug mode, so you get wonderful stream of feedback.  Use terraform without options to get a short help.

----

# Optional install gcloud cli tool

`gcloud` exec is google CLI tool to control and consult environments. It's very handy and uses the same keys as terraform does, so I recomment installing it so you can consult the ips of servers in your env:

    glenn@slicky:~/repos/terraform$ gcloud compute instances list
    NAME       ZONE            MACHINE_TYPE               PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP     STATUS
    grb-db-0    europe-west1-d  custom (1 vCPU, 2.00 GiB)               10.132.0.5   204.255.58.142  RUNNING

# Sandbox Uses

Currently, we have:

 - Build a fresh postgis DB for GRB data usage

