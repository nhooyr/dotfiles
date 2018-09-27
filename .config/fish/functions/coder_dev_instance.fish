function coder_dev_instance
  gcloud compute instances describe test-anmol | rg -o 'natIP: (.*)' -r '$1'
end