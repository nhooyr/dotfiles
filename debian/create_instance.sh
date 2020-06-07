#!/bin/sh
set -eu

gcloud --configuration=nhooyr-coder compute instances create xayah \
  --zone=northamerica-northeast1-a \
  --machine-type=e2-custom-8-16384 \
  --subnet=main \
  --address=xayah \
  --private-network-ip=xayah-internal \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --image=debian-10-buster-v20200521 \
  --image-project=debian-cloud \
  --boot-disk-size=128GB \
  --boot-disk-type=pd-ssd
