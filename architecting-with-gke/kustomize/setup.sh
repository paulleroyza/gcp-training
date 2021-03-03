#!/bin/bash

export my_zone=europe-west1-d
export my_cluster=demo-cluster
export project_id=$DEVSHELL_PROJECT_ID

source <(kubectl completion bash)
gcloud container clusters create $my_cluster --num-nodes 3  --enable-ip-alias --zone $my_zone
gcloud container clusters get-credentials $my_cluster --zone $my_zone

mkdir -p temp/app
cat > temp/app/app.py <<EOF
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
  return "Built Locally and Pushed\n"

@app.route("/version")
def version():
  return "Helloworld 1.0\n"

if __name__ == "__main__":
  app.run(host='0.0.0.0',port=80)
EOF

cat > temp/app/requirements.txt <<EOF
Flask==0.12
uwsgi==2.0.15
EOF

cat > temp/app/Dockerfile <<EOF
FROM ubuntu:18.04
RUN apt-get update -y && \
    apt-get install -y python3-pip python3-dev
COPY requirements.txt /app/requirements.txt
WORKDIR /app
RUN pip3 install -r requirements.txt
COPY app.py /app
ENTRYPOINT ["python3", "app.py"]
EOF

gcloud builds submit --tag gcr.io/$project_id/pyserver:v2 temp/app/.
gcloud container images add-tag gcr.io/$project_id/pyserver:v2 gcr.io/$project_id/pyserver:latest gcr.io/$project_id/pyserver:remote --quiet

echo Please edit bases/applications/helloworld-app.yaml and set to your project ID !!

