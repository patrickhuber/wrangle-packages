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
  resource_type=$(yq e '.resource.type' $resource_file)
  if [ "$resource_type" != "github-release" ]; then
    echo "skip: $package, unknown release type '$resource_type'"
    continue;
  fi
  
  # get latest version from the owner/repository  
  github_release_owner=$(yq e '.resource.source.owner' $resource_file)
  if [ "$github_release_owner" == "null" ]; then
    echo "skip: $package, missing github-release.source.owner"
    continue;
  fi

  github_release_repository=$(yq e '.resource.source.repository' $resource_file)
  if [ "$github_release_repository" == "null" ]; then
    echo "skip: $package, missing github-release.source.repository"
    continue;
  fi

  # extract the version regex
  tag_filter=$(yq e '.resource.source.tag_filter' $resource_file)
  github_release_version_regex=$(yq e '.resource.source.version-regex' $resource_file)
  if [ "$github_release_version_regex" == "null" ]; then
    github_release_version_regex=".*"
  fi

  # get the latest version and use the version regex to filter (the meaning of this is meant to allow pinning, so rethinking may be necessary)
  github_release_latest=$(curl -s https://api.github.com/repos/$github_release_owner/$github_release_repository/releases/latest | jq .tag_name -r | grep -E -o "${github_release_version_regex}")
  if [ "$github_release_latest" == "" ]; then
    echo "skip: $package, github release version unable to be parsed with expression '$github_release_version_regex'"
    continue;
  fi
    
  # check for the state file 
  state_file="$package_dir/state.yml"            

  if [ -f "$state_file" ]; then
    version=$(yq e '.version' $state_file)
    if [ "$version" == "$github_release_latest" ]; then
        echo "skip: $package, on latest version"
        continue;
    fi
  else
    echo "version: $github_release_latest" > $state_file
  fi

  export version=$(echo ${github_release_latest})
  package_version_dir="$package_dir/$version"

  # write the latest version out to the latest file
  yq e ".version = env(version)" -i $state_file  

  # create the package version 
  mkdir -p "$package_dir/$version"

  # run the template to generate the package file
  renderizer --settings=$package_dir/platforms.yml --settings=$package_dir/resource.yml --settings=$package_dir/state.yml $package_dir/template.yml > $package_version_dir/package.yml
done