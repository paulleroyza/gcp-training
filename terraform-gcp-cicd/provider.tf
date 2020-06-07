provider "google" {
  credentials = file("service_account.json")
  project     = "PROJECT"
  version = ">= 2.5.1"
}

// Version Check
terraform {
  required_version = ">= 0.12.6"
}
