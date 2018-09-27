function coder_prod_instance
  gcloud --project coder-production compute instances describe test-anmol-prod | rg -o 'natIP: (.*)' -r '$1'
end