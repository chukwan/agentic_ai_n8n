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

# Cloud SQL User (Resource block removed - let instance deletion handle cleanup)

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

# Output "db_password" removed as the user resource was removed

# Output "db_user" removed as the resource was removed

output "db_name" {
  description = "Name of the n8n database"
  value       = google_sql_database.n8n_database.name
}