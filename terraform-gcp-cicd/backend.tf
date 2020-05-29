terraform {
  backend "gcs" {
    bucket  = "BUCKET"
    prefix  = "terraform/state"
  }
}