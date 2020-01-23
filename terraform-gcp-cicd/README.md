# Terraform scaffold for GCP

This repo is for setting up a terraform CICD pipeline using source repositories and cloud build. run `gcloud config set project <project>` to select the project to deploy to before running the script. This runs on Cloud Shell and MAC OS.

If this is run in cloud shell and the project is set it will:
- enable the APIs
- clone the community builder for cloud build/terraform
- create the terraform service account
- create the source repo for the lab code
- download the service account key
- download the skeleton code for the state storage and google provider
- download the cloudbuild.yaml file
- set the project and bucket in the skeleton code
- create the state bucket
- create the build trigger off cloud source repos
- build the terraform builder
- put the students in the directory to do a git push to start updateing infrastructure. 

Before running this script in class, each of these steps should be done manually.