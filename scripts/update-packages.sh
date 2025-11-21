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

  # get all releases from github and extract versions that match the version regex
  all_versions=$(curl -s https://api.github.com/repos/$github_release_owner/$github_release_repository/releases | jq -r '.[].tag_name' | grep -E -o "${github_release_version_regex}" | sort -V)
  
  if [ -z "$all_versions" ]; then
    echo "skip: $package, no github releases found or unable to parse versions"
    continue;
  fi
  
  # get the latest version from all versions
  github_release_latest=$(echo "$all_versions" | tail -1)
  
  if [ "$github_release_latest" == "" ]; then
    echo "skip: $package, github release version unable to be parsed with expression '$github_release_version_regex'"
    continue;
  fi
    
  # check for the state file 
  state_file="$package_dir/state.yml"            

  # determine the starting version
  if [ -f "$state_file" ]; then
    current_version=$(yq e '.version' $state_file)
    if [ "$current_version" == "$github_release_latest" ]; then
        echo "skip: $package, on latest version"
        continue;
    fi
    # filter versions to only those newer than current version using semantic version sorting
    # this works by: combining current+all versions, sorting semantically, finding current version position, 
    # then taking everything after it (tail -n +2 skips the current version itself)
    versions_to_generate=$(echo -e "$current_version\n$all_versions" | sort -V -u | sed -n "/$current_version/,\$p" | tail -n +2)
  else
    # if no state file, generate only the latest version
    versions_to_generate="$github_release_latest"
    echo "version: $github_release_latest" > $state_file
  fi

  # generate package.yml for each version
  while read version; do
    if [ -z "$version" ]; then
      continue
    fi
    
    echo "generating version: $version"
    export version
    package_version_dir="$package_dir/$version"

    # create the package version directory
    mkdir -p "$package_version_dir"

    # temporarily update state.yml with current version for template rendering
    yq e ".version = env(version)" -i $state_file

    # run the template to generate the package file
    renderizer --settings=$package_dir/platforms.yml --settings=$package_dir/resource.yml --settings=$package_dir/state.yml $package_dir/template.yml > $package_version_dir/package.yml
  done <<< "$versions_to_generate"
  
  # write the final latest version to state file
  export version=$(echo ${github_release_latest})
  yq e ".version = env(version)" -i $state_file
done