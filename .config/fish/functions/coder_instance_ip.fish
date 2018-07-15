function coder_instance_ip
  gcloud compute instances describe test-anmol | rg -o 'natIP: (.*)' -r '$1'
end