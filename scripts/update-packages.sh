#!/bin/bash

# install tools
apt-get update
apt-get install wget jq -y
wget 'https://github.com/mikefarah/yq/releases/download/2.4.0/yq_linux_amd64' -O ~/yq
chmod +x ~/yq
mv ~/yq /usr/local/bin/yq

# enumerate packages looking for resource.yml and template.yml files
for package in feed; do
  ls -l $package
done