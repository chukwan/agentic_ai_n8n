# n8n GCP Deployment Reactivation Guide

This guide outlines the steps to redeploy the n8n server on GCP using Terraform and Docker Compose, based on the configuration established previously.

## Prerequisites

1.  **Google Cloud SDK (`gcloud`)**: Ensure `gcloud` is installed and authenticated to your GCP project (`strong-surfer-456313-q0`).
    *   Install: [https://cloud.google.com/sdk/docs/install](https://cloud.google.com/sdk/docs/install)
    *   Authenticate: Run `gcloud auth application-default login` in your terminal.
2.  **Terraform**: Ensure Terraform is installed.
    *   Install: [https://developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads)
    *   Verify: Run `terraform -version` in your terminal.
3.  **Project Directory**: Perform these steps in the directory containing the `main.tf` file (`y:/AI projects/agentic_ai_n8n`).

## Step 1: Terraform Infrastructure Deployment

1.  **Save Terraform Configuration:** Ensure the following content is saved as `main.tf` in your project directory.

    ```terraform
    # Terraform Configuration for n8n Deployment on GCP

    terraform {
      required_providers {
        google = {
          source  = "hashicorp/google"
          version = "~> 5.0"
        }
        random = {
          source  = "hashicorp/random"
          version = "~> 3.0"
        }
      }
    }

    provider "google" {
      project = var.gcp_project_id
      region  = var.gcp_region
    }

    provider "google-beta" {
      project = var.gcp_project_id
      region  = var.gcp_region
    }

    variable "gcp_project_id" {
      description = "Your GCP Project ID"
      type        = string
      default     = "strong-surfer-456313-q0" # Updated Project ID
    }

    variable "gcp_region" {
      description = "GCP Region"
      type        = string
      default     = "asia-east1" # Updated Region
    }

    variable "gcp_zone" {
      description = "GCP Zone"
      type        = string
      default     = "asia-east1-a" # Updated Zone
    }

    variable "gce_machine_type" {
      description = "GCE Machine Type"
      type        = string
      default     = "e2-standard-4" # Updated Machine Type
    }

    variable "cloud_sql_tier" {
      description = "Cloud SQL Machine Tier"
      type        = string
      default     = "db-g1-small" # Updated SQL Tier
    }

    variable "cloud_sql_db_name" {
      description = "Name for the n8n database"
      type        = string
      default     = "n8n_database"
    }

    variable "cloud_sql_user_name" {
      description = "Username for the n8n database user"
      type        = string
      default     = "n8n_user"
    }

    variable "n8n_instance_name" {
      description = "Base name for n8n related resources"
      type        = string
      default     = "n8n-server"
    }

    # --- Networking (Using Default VPC) ---
    data "google_compute_network" "default" {
      name = "default"
    }

    # --- Random Password for DB ---
    resource "random_password" "db_password" {
      length           = 20
      special          = true
      override_special = "_%@"
    }

    # --- Cloud SQL for PostgreSQL ---
    # Enable necessary APIs
    resource "google_project_service" "compute" {
      project = var.gcp_project_id
      service = "compute.googleapis.com"
      disable_on_destroy = false
    }

    resource "google_project_service" "sqladmin" {
      project = var.gcp_project_id
      service = "sqladmin.googleapis.com"
      disable_on_destroy = false
    }

    resource "google_project_service" "servicenetworking" {
      project = var.gcp_project_id
      service = "servicenetworking.googleapis.com"
      disable_on_destroy = false
    }

    # Allocate IP range for Service Networking (required for Cloud SQL Private IP)
    resource "google_compute_global_address" "private_ip_alloc" {
      provider      = google-beta
      project       = var.gcp_project_id
      name          = "n8n-sql-private-ip-alloc"
      purpose       = "VPC_PEERING"
      address_type  = "INTERNAL"
      prefix_length = 16 # Adjust if needed, ensure it doesn't overlap
      network       = data.google_compute_network.default.id
      depends_on = [google_project_service.servicenetworking]
    }

    resource "google_service_networking_connection" "private_vpc_connection" {
      provider                = google-beta
      network                 = data.google_compute_network.default.id
      service                 = "servicenetworking.googleapis.com"
      reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
      depends_on = [google_project_service.servicenetworking]
    }

    # Cloud SQL Instance
    resource "google_sql_database_instance" "n8n_db_instance" {
      provider            = google-beta
      project             = var.gcp_project_id
      name                = "${var.n8n_instance_name}-db"
      region              = var.gcp_region
      database_version    = "POSTGRES_15" # Or choose another supported version
      settings {
        tier = var.cloud_sql_tier
        ip_configuration {
          ipv4_enabled    = false # Disable public IP
          private_network = data.google_compute_network.default.id
        }
        backup_configuration {
          enabled = true
          # binary_log_enabled = true # Removed: Not applicable to PostgreSQL
        }
        availability_type = "REGIONAL" # Consider ZONAL if HA isn't critical and cost is a factor
      }
      deletion_protection = false # Set to true for production
      depends_on = [google_service_networking_connection.private_vpc_connection]
    }

    # Cloud SQL Database
    resource "google_sql_database" "n8n_database" {
      project  = var.gcp_project_id
      name     = var.cloud_sql_db_name
      instance = google_sql_database_instance.n8n_db_instance.name
    }

    # Cloud SQL User
    resource "google_sql_user" "n8n_user" {
      project  = var.gcp_project_id
      name     = var.cloud_sql_user_name
      instance = google_sql_database_instance.n8n_db_instance.name
      password = random_password.db_password.result
    }

    # --- GCE VM Instance ---
    resource "google_compute_instance" "n8n_vm" {
      project      = var.gcp_project_id
      name         = var.n8n_instance_name
      machine_type = var.gce_machine_type
      zone         = var.gcp_zone
      tags         = ["n8n-server", "allow-ssh", "allow-n8n-ui", "allow-n8n-mcp"]

      boot_disk {
        initialize_params {
          image = "debian-cloud/debian-11" # Or ubuntu-os-cloud/ubuntu-2204-lts
          size  = 30 # Increased size slightly for e2-standard-4
        }
      }

      network_interface {
        network = data.google_compute_network.default.name
        access_config {
          # Ephemeral external IP
        }
      }

      metadata_startup_script = <<-EOF
        #!/bin/bash
        echo "VM Startup Script Executed" > /tmp/startup_log.txt
        # Docker installation will be handled manually or via separate script
        EOF

      service_account {
        scopes = ["cloud-platform"]
      }
      depends_on = [google_project_service.compute]
    }

    # --- Firewall Rules ---
    resource "google_compute_firewall" "allow_ssh" {
      project = var.gcp_project_id
      name    = "${var.n8n_instance_name}-allow-ssh"
      network = data.google_compute_network.default.name
      allow {
        protocol = "tcp"
        ports    = ["22"]
      }
      target_tags   = ["allow-ssh"]
      source_ranges = ["0.0.0.0/0"] # WARNING: Restrict in production!
      depends_on = [google_project_service.compute]
    }

    resource "google_compute_firewall" "allow_n8n_ui" {
      project = var.gcp_project_id
      name    = "${var.n8n_instance_name}-allow-n8n-ui"
      network = data.google_compute_network.default.name
      allow {
        protocol = "tcp"
        ports    = ["5678"] # Default n8n port
      }
      target_tags   = ["allow-n8n-ui"]
      source_ranges = ["0.0.0.0/0"] # WARNING: Restrict in production!
      depends_on = [google_project_service.compute]
    }

    resource "google_compute_firewall" "allow_n8n_mcp" {
      project = var.gcp_project_id
      name    = "${var.n8n_instance_name}-allow-n8n-mcp"
      network = data.google_compute_network.default.name
      allow {
        protocol = "tcp"
        ports    = ["5679"] # Example MCP port - VERIFY THIS!
      }
      target_tags   = ["allow-n8n-mcp"]
      source_ranges = ["0.0.0.0/0"] # WARNING: Restrict in production!
      depends_on = [google_project_service.compute]
    }

    # --- Outputs ---
    output "gce_instance_external_ip" {
      description = "External IP address of the n8n GCE VM"
      value       = google_compute_instance.n8n_vm.network_interface[0].access_config[0].nat_ip
    }

    output "gce_instance_internal_ip" {
      description = "Internal IP address of the n8n GCE VM"
      value       = google_compute_instance.n8n_vm.network_interface[0].network_ip
    }

    output "cloud_sql_instance_private_ip" {
      description = "Private IP address of the Cloud SQL instance"
      value       = google_sql_database_instance.n8n_db_instance.private_ip_address
    }

    output "cloud_sql_instance_connection_name" {
      description = "Connection name of the Cloud SQL instance (useful for Cloud SQL Proxy)"
      value       = google_sql_database_instance.n8n_db_instance.connection_name
    }

    output "db_password" {
      description = "Generated password for the n8n database user (sensitive)"
      value       = random_password.db_password.result
      sensitive   = true
    }

    output "db_user" {
      description = "Username for the n8n database user"
      value       = google_sql_user.n8n_user.name
    }

    output "db_name" {
      description = "Name of the n8n database"
      value       = google_sql_database.n8n_database.name
    }
    ```

2.  **Run Terraform Commands:** Open a terminal in the project directory and run:
    ```bash
    terraform init
    terraform plan
    terraform apply # Confirm with 'yes'
    ```
    Wait for `terraform apply` to complete.

3.  **Get Outputs:** Run `terraform output` to get the necessary IP addresses and database details. Keep these handy. You will especially need the database password, which you can retrieve specifically with `terraform output db_password`.

## Step 2: Configure GCE VM

1.  **SSH into VM:** Use the `gcloud` command (replace zone and project if they differ from the Terraform variables):
    ```bash
    gcloud compute ssh n8n-server --zone asia-east1-a --project strong-surfer-456313-q0
    ```
    Confirm host key and create SSH keys if prompted.

2.  **Install Docker & Docker Compose:** Run these commands inside the SSH session on the VM:
    ```bash
    # Update package list
    sudo apt update

    # Install prerequisites
    sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine and Compose plugin
    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker $USER

    # Apply group changes (or log out and log back in)
    newgrp docker

    # Verify installation
    docker --version
    docker compose version
    ```

## Step 3: Deploy n8n

1.  **Create `docker-compose.yml`:** While still SSH'd into the VM, create the file:
    ```bash
    nano docker-compose.yml
    ```
2.  **Paste Configuration:** Paste the following content into `nano`.
    *   **CRITICAL:** Replace `Your_DB_Password_From_Terraform_Output` with the actual password obtained from `terraform output db_password`.
    *   **CRITICAL:** Replace `Your_Cloud_SQL_Private_IP_Address` with the actual private IP from `terraform output cloud_sql_instance_private_ip`.
    *   **IMPORTANT:** Store the `N8N_ENCRYPTION_KEY` and `N8N_MCP_SERVER_API_KEY` securely.
    *   **VERIFY:** Check the n8n documentation for the correct MCP environment variable names and port (`5679` is a placeholder).

    ```yaml
    version: '3.7'

    services:
      n8n:
        image: n8nio/n8n
        restart: always
        ports:
          - "5678:5678" # n8n UI/API port
          - "5679:5679" # Example: MCP port (Verify from n8n docs!)
        environment:
          - GENERIC_TIMEZONE=Asia/Hong_Kong
          # --- IMPORTANT: Store this key securely! ---
          - N8N_ENCRYPTION_KEY=zj!_@%9pL@8rV#wG$kF7sD2mQ5tN1xY0 # Regenerate if desired

          # --- PostgreSQL Configuration ---
          - DB_TYPE=postgresdb
          - DB_POSTGRESDB_HOST=Your_Cloud_SQL_Private_IP_Address # Replace!
          - DB_POSTGRESDB_PORT=5432
          - DB_POSTGRESDB_DATABASE=n8n_database # From Terraform output
          - DB_POSTGRESDB_USER=n8n_user # From Terraform output
          # --- Replace with your actual password below ---
          - DB_POSTGRESDB_PASSWORD=Your_DB_Password_From_Terraform_Output

          # --- MCP Server Configuration (Verify variable names & port from n8n docs!) ---
          - N8N_MCP_SERVER_ENABLED=true # Hypothetical - Check n8n docs
          - N8N_MCP_SERVER_PORT=5679    # Hypothetical - Check n8n docs (Ensure matches 'ports')
          # --- IMPORTANT: Store this API key securely! ---
          - N8N_MCP_SERVER_API_KEY=mcp_@k3Y_sE9cR@t_pW5d_gH1jL!7zX # Regenerate if desired

        volumes:
          - n8n_data:/home/node/.n8n

    volumes:
      n8n_data:
    ```

3.  **Save and Exit `nano`:** Press `Ctrl+X`, then `Y`, then `Enter`.

4.  **Start n8n:**
    ```bash
    docker compose up -d
    ```

5.  **Check Status:**
    ```bash
    docker compose ps
    docker compose logs n8n
    ```

## Step 4: Access n8n

*   Open your browser and navigate to `http://<GCE_EXTERNAL_IP>:5678` (replace `<GCE_EXTERNAL_IP>` with the IP from `terraform output gce_instance_external_ip`).
*   You may encounter the secure cookie error. To resolve this permanently, you need a domain name pointed to the external IP and configure HTTPS (using Nginx/Certbot, not covered in this basic guide).
*   **Temporary Workaround (Not Recommended for Security):** Add `N8N_SECURE_COOKIE=false` to the `environment` section in `docker-compose.yml` and run `docker compose up -d` again.

## Step 5: Destroy Infrastructure (When Finished)

*   To remove all GCP resources created by Terraform and stop incurring costs, run the following command in your **local terminal** (in the project directory):
    ```bash
    terraform destroy # Confirm with 'yes'
    ```

This guide should provide a clear path to redeploy your n8n instance. Remember to handle the sensitive values (DB password, encryption key, MCP API key) securely.