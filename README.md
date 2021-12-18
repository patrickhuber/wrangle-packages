# wrangle-packages
a feed of wrangle packages

## Creating a New Package

prerequisites:
1. Install [renderizer](https://github.com/gomatic/renderizer/releases/latest)

instructions:
1. Under the 'feed' directory, create a folder for the package
2. Create a 'resource.yml' file to give information on how to fetch new versions of the package. 
3. Create a 'platforms.yml' file to scope platforms and architectures.
4. Create a 'template.yml' file to render new package versions.
5. \[Optional\] Create a 'state.yml file to show what version to generate

### 'resource.yml'

example

```yaml
resource:
  name: github-release
  type: github-release
  source:
    owner: patrickhuber
    repository: shim
    version-regex: '[0-9]+\.[0-9]+\.[0-9]+'
```

### 'platforms.yml'

example 

```yaml
platforms:
- platform: linux
  architectures: [amd64]
- platform: darwin
  architectures: [amd64]
- platform: windows
  architectures: [amd64]  
```

### 'template.yml'

example 

```yaml
package: 
  name: shim
  version: {{ .version }}
  targets:
  {{- range .platforms -}}
  {{- $platform := .platform -}}
  {{- range .architectures -}}
  {{- $architecture := . }}
  - platform: {{ $platform }}
    architecture: {{ $architecture }}
    tasks:
    {{- $archive := ".tar.gz" -}}
    {{- if eq $platform "windows" -}}
        {{- $archive = ".zip" -}}
    {{- end }}
    - download:    
        url: https://github.com/patrickhuber/shim/releases/download/v{{ $.version }}/shim-{{ $.version }}-{{ $platform }}-{{ $architecture }}{{ $archive }}
        out: shim-{{ $.version }}-{{ $platform }}-{{ $architecture }}{{ $archive }}
    - extract:
        archive: shim-{{ $.version }}-{{ $platform }}-{{ $architecture }}{{ $archive }}
  {{- end -}}
  {{- end -}}
```
### 'state.yml'

```yaml
version: 0.0.1
```

### testing generation

```bash
export $package=shim
export $version=0.0.1
export $package_dir="feed/$package"
export $package_version_dir="$package_dir/$version"

mkdir -p $package_version_dir
renderizer --settings=$package_dir/platforms.yml --settings=$package_dir/resource.yml --settings=$package_dir/state.yml $package_dir/template.yml > $package_version_dir/package.yml
```