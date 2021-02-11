#!/bin/bash

# loop through all the packages
ls feed -1 | while read package
do
  echo "$package"

  package_dir="feed/$package"
  resource_file="$package_dir/resource.yml"
  # check for the $resource_file, if it doesn't exist, skip this package
  if [ ! -f $resource_file ]; then
    echo "skip: $package, missing resource file '$resource_file'"
    continue;
  fi

  # check the type of the resource, skip if not github-release
  resource_type=$(yq r $resource_file resource.type)
  if [ $resource_type != "github-release" ]; then
    echo "skip: $package, unknown release type '$resource_type'"
    continue;
  fi
  
  # get latest version from the owner/repository
  github_release_owner=$(yq r $resource_file resource.source.owner )
  github_release_repository=$(yq r $resource_file resource.source.repository )

  github_release_latest=$(curl -s https://api.github.com/repos/$github_release_owner/$github_release_repository/releases/latest | jq .name -r)
  github_release_latest=$(echo ${github_release_latest//v})
  # check for the state file
 
  state_file="$package_dir/state.yml"            

  if [ -f $state_file ]; then
    version=$(yq r $state_file version)
    if [ $version == $github_release_latest ]; then
        echo "skip: $package, on latest version"
        continue;
    fi
  fi

  version=$(echo ${github_release_latest})
  package_version_dir="$package_dir/$version"

  # write the latest version out to the latest file
  yq w $state_file version $version
  cat $state_file

  # create the package version 
  mkdir -p "$package_dir/$version"

  # run the template to generate the package file
  renderizer --settings=$package_dir/platforms.yml --settings=$package_dir/resource.yml --settings=$package_dir/state.yml $package_dir/template.yml > $package_version_dir/package.yml
done