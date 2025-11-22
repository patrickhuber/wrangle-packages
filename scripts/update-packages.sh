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

  # check for the state file first to avoid unnecessary API calls
  state_file="$package_dir/state.yml"
  
  # get the latest version first to check if we need to update
  github_release_latest=$(curl -s https://api.github.com/repos/$github_release_owner/$github_release_repository/releases/latest | jq .tag_name -r | grep -E -o "${github_release_version_regex}" || true)
  if [ "$github_release_latest" == "" ]; then
    echo "skip: $package, github release version unable to be parsed with expression '$github_release_version_regex'"
    continue;
  fi
  
  # check if we're already on the latest version to avoid pagination
  if [ -f "$state_file" ]; then
    current_version=$(yq e '.version' $state_file)
    if [ "$current_version" == "$github_release_latest" ]; then
        echo "skip: $package, on latest version"
        continue;
    fi
  fi

  # get all releases from github with pagination and extract versions that match the version regex
  # GitHub API returns max 100 items per page, so we need to paginate through all pages
  page=1
  all_versions=""
  while true; do
    releases=$(curl -s "https://api.github.com/repos/$github_release_owner/$github_release_repository/releases?per_page=100&page=$page")
    
    # Check if we got an empty array (no more pages)
    if [ "$releases" = "[]" ] || [ -z "$releases" ]; then
      break
    fi
    
    # Extract tag names from this page
    page_versions=$(echo "$releases" | jq -r '.[].tag_name' 2>/dev/null | grep -E -o "${github_release_version_regex}" || true)
    
    # If no versions found on this page, we're done
    if [ -z "$page_versions" ]; then
      break
    fi
    
    # Append to all versions (only if page_versions is non-empty)
    all_versions="$all_versions$page_versions"$'\n'
    
    # Check if we got less than 100 items, meaning this is the last page
    items_count=$(echo "$releases" | jq '. | length' 2>/dev/null || echo "0")
    if [ -z "$items_count" ] || [ "$items_count" -lt 100 ]; then
      break
    fi
    
    page=$((page + 1))
  done
  
  # Remove empty lines from all_versions (keep chronological order from API)
  all_versions=$(echo "$all_versions" | grep -v '^$')
  
  if [ -z "$all_versions" ]; then
    echo "skip: $package, no github releases found or unable to parse versions"
    continue;
  fi
    
  # determine which versions to generate
  if [ -f "$state_file" ]; then
    # filter versions to only those newer than current version using chronological order from API
    # GitHub API returns releases in reverse chronological order (newest first)
    # we collect versions until we find the current version, then reverse to get oldest-to-newest
    found_current=false
    temp_versions=()
    while IFS= read -r version; do
      if [ "$version" == "$current_version" ]; then
        found_current=true
        break
      fi
      temp_versions+=("$version")
    done <<< "$all_versions"
    
    # If current version not found in releases, generate all versions
    if [ "$found_current" = false ]; then
      echo "warning: $package, current version '$current_version' not found in releases, generating all versions"
    fi
    
    # Reverse array to get oldest-to-newest order
    versions_to_generate=""
    for ((i=${#temp_versions[@]}-1; i>=0; i--)); do
      versions_to_generate="$versions_to_generate${temp_versions[i]}"$'\n'
    done
    
    # Remove trailing newline
    versions_to_generate=$(echo "$versions_to_generate" | grep -v '^$')
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