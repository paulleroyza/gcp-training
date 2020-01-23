#!/bin/bash

#enable APIs
gcloud services enable containerregistry.googleapis.com
gcloud services enable sourcerepo.googleapis.com
gcloud services enable cloudbuild.googleapis.com

echo "Just waiting a bit"
sleep 20
#variables
FOLDER=cloud-builders-community
URL=https://github.com/GoogleCloudPlatform/cloud-builders-community.git
PROJECT=$(gcloud config list --format="value(core.project)")
TF_VER=$(curl https://www.terraform.io/downloads.html | grep -E -o '\s0\.[[:digit:]]{1,2}\.[[:digit:]]{1,2}' | sed 's/ //g')
CUR_VER=$(gcloud container images list-tags gcr.io/$PROJECT/terraform \
	--format="value(TAGS)"| grep latest | grep -o -E '[[:digit:]]{1}\.[[:digit:]]{1,2}\.[[:digit:]]{1,2}')
BUCKET=${PROJECT}-terraform
#clone repo

if [ ! -d "$FOLDER" ] ; then
    git clone $URL $FOLDER
else
    cd "$FOLDER"
    git pull $URL
fi

#create service account
gcloud iam service-accounts create terraform \
    --description "Service account for Terraform Deployments" \
    --display-name "Terraform Deployment"

#prepare config
gcloud source repos create terraform
gcloud source repos clone terraform --project=$PROJECT

cd terraform
#generate SA key
gcloud iam service-accounts keys create service_account.json \
  --iam-account terraform@${PROJECT}.iam.gserviceaccount.com

#give sa editor role
gcloud projects add-iam-policy-binding $PROJECT \
  --member serviceAccount:terraform@${PROJECT}.iam.gserviceaccount.com \
  --role roles/editor

#Create skeleton files
cat >provider.tf <<EOL
provider "google" {
  credentials = file("service_account.json")
  project     = "$PROJECT"
  version = ">= 2.5.1"
}

// Version Check
terraform {
  required_version = ">= 0.12.6"
}
EOL
cat >backend.tf <<EOL
terraform {
  backend "gcs" {
    bucket  = "$BUCKET"
    prefix  = "terraform/state"
  }
}
EOL
cat >cloudbuild.yaml <<EOL
steps:
- name: 'gcr.io/${PROJECT_ID}/terraform'
  args: ['init']
- name: 'gcr.io/${PROJECT_ID}/terraform'
  args: ['apply','-auto-approve']
EOL
gsutil cp gs://website.demo.leroy.global/provider.tf ./
gsutil cp gs://website.demo.leroy.global/backend.tf ./
gsutil cp gs://website.demo.leroy.global/cloudbuild.yaml ./

gsutil mb gs://$BUCKET

#create cloud build trigger
gcloud beta builds triggers create cloud-source-repositories \
    --repo=terraform \
    --branch-pattern=".*" \
    --build-config=cloudbuild.yaml 


#create the builder needed for cloud build
cd ../$FOLDER/terraform

if [[ $TF_VER != $CUR_VER ]]
then
  echo "New Build"
  gcloud --project=$PROJECT builds submit --config=cloudbuild.yaml \
  --substitutions=_TERRAFORM_VERSION="$TF_VER",_TERRAFORM_VERSION_SHA256SUM="$(curl "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_SHA256SUMS" | grep amd64 | grep linux | awk '{ print $1 }')"
fi

#lets get back to repo directory and go
cd ../../terraform


