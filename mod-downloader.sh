
#!/usr/bin/env bash
set -euo pipefail

API="https://api.modrinth.com/v2"
UA="modrinth-curl-downloader/2.0"

MC_VERSION="${1:-}"
LOADER="${2:-}"

declare -A SEEN=()
declare -A DOWNLOADED=()
declare -A PROJECT_NAMES=()

request() {
    curl -fsSL --retry 2 \
        -H "User-Agent: $UA" "$1"
}

urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

# Download a specific version and recursively resolve its dependencies.
download_version() {
    local version_id="$1"
    local version project_id title file filename url dep
    local dep_type dep_version dep_project dep_slug
    local versions params filter_url selected

    # Prevent dependency cycles and duplicate downloads.
    [[ -n "${SEEN[$version_id]+yes}" ]] && return 0
    SEEN["$version_id"]=1

    version=$(request "$API/version/$version_id") || {
        echo "WARNING: cannot fetch version $version_id" >&2
        return 1
    }

    project_id=$(jq -r '.project_id' <<< "$version")
    title=$(jq -r '.name // .version_number' <<< "$version")

    echo
    echo "Processing: $title"

    # Resolve required dependencies first.
    while IFS= read -r dep; do
        dep_type=$(jq -r '.dependency_type' <<< "$dep")
        [[ "$dep_type" == "required" ]] || continue

        dep_version=$(jq -r '.version_id // empty' <<< "$dep")
        dep_project=$(jq -r '.project_id // empty' <<< "$dep")

        if [[ -n "$dep_version" ]]; then
            download_version "$dep_version" || {
                echo "WARNING: dependency failed: $dep_version" >&2
            }
        elif [[ -n "$dep_project" ]]; then
            dep_slug=$(jq -r '.slug // empty' <<< "$dep")
            [[ -n "$dep_slug" ]] || dep_slug="$dep_project"

            params=()
            [[ -n "$MC_VERSION" ]] &&
                params+=(--data-urlencode "game_versions=[\"$MC_VERSION\"]")
            [[ "$LOADER" != "any" ]] &&
                params+=(--data-urlencode "loaders=[\"$LOADER\"]")

            versions=$(curl -fsSL -G \
                -H "User-Agent: $UA" \
                "${params[@]}" \
                "$API/project/$dep_slug/version") || {
                echo "WARNING: cannot find versions for $dep_slug" >&2
                continue
            }

            selected=$(jq -r '.[0].id // empty' <<< "$versions")
            if [[ -n "$selected" ]]; then
                download_version "$selected" || true
            else
                echo "WARNING: no compatible version for $dep_slug" >&2
            fi
        fi
    done < <(jq -c '.dependencies[]?' <<< "$version")

    # Select primary file, or the first file if none is marked primary.
    file=$(jq -c '
        [.files[] | select(.primary == true)] as $p |
        if ($p | length) > 0 then $p[0] else .files[0] end
    ' <<< "$version")

    url=$(jq -r '.url // empty' <<< "$file")
    filename=$(jq -r '.filename // empty' <<< "$file")

    [[ -n "$url" && -n "$filename" ]] || {
        echo "WARNING: no downloadable file for $title" >&2
        return 0
    }

    # Only accept Modrinth CDN downloads.
    [[ "$url" == https://cdn.modrinth.com/* ]] || {
        echo "WARNING: refusing unexpected URL: $url" >&2
        return 1
    }

    # Avoid overwriting files already downloaded by this script.
    if [[ -n "${DOWNLOADED[$filename]+yes}" ]]; then
        return 0
    fi

    echo "Downloading: $filename"
    curl -fL --retry 2 --show-error --progress-bar \
        -H "User-Agent: $UA" \
        -o "$filename" "$url"

    DOWNLOADED["$filename"]=1
    echo "Saved: $filename"
}

echo "=== Modrinth Downloader + Dependencies ==="

if [[ -z "$MC_VERSION" ]]; then
    read -rp "Minecraft version (e.g. 1.21.1): " MC_VERSION
fi

if [[ -z "$LOADER" ]]; then
    read -rp "Loader (fabric/forge/neoforge/quilt/any): " LOADER
fi

LOADER="${LOADER:-any}"

read -rp "Search for a mod: " QUERY
[[ -n "$QUERY" ]] || exit 1

SEARCH_URL="$API/search?query=$(urlencode "$QUERY")&facets=%5B%5B%22project_type%3Amod%22%5D%5D&limit=15"
RESULT=$(request "$SEARCH_URL")

COUNT=$(jq '.hits | length' <<< "$RESULT")
(( COUNT > 0 )) || { echo "No mods found."; exit 1; }

jq -r '.hits | to_entries[] |
    "\(.key + 1). \(.value.title) — \(.value.author)\n   \(.value.description)\n"' \
    <<< "$RESULT"

read -rp "Choose a mod number (0 to cancel): " CHOICE
[[ "$CHOICE" =~ ^[0-9]+$ ]] || exit 1
(( CHOICE > 0 && CHOICE <= COUNT )) || exit 0

SLUG=$(jq -r --argjson n "$CHOICE" '.hits[$n - 1].slug' <<< "$RESULT")
TITLE=$(jq -r --argjson n "$CHOICE" '.hits[$n - 1].title' <<< "$RESULT")

PARAMS=()
[[ -n "$MC_VERSION" ]] &&
    PARAMS+=(--data-urlencode "game_versions=[\"$MC_VERSION\"]")
[[ "$LOADER" != "any" ]] &&
    PARAMS+=(--data-urlencode "loaders=[\"$LOADER\"]")

VERSIONS=$(curl -fsSL -G \
    -H "User-Agent: $UA" \
    "${PARAMS[@]}" \
    "$API/project/$SLUG/version")

VC=$(jq 'length' <<< "$VERSIONS")
(( VC > 0 )) || { echo "No compatible versions found."; exit 1; }

jq -r 'to_entries[] |
    "\(.key + 1). \(.value.version_number) [\(.value.version_type)] — MC \(.value.game_versions | join(", ")) — \(.value.loaders | join(", "))"' \
    <<< "$VERSIONS"

read -rp "Choose a version number (0 to cancel): " VCHOICE
[[ "$VCHOICE" =~ ^[0-9]+$ ]] || exit 1
(( VCHOICE > 0 && VCHOICE <= VC )) || exit 0

VERSION_ID=$(jq -r --argjson n "$VCHOICE" '.[$n - 1].id' <<< "$VERSIONS")

echo
echo "Selected: $TITLE"
echo "Resolving required dependencies..."
download_version "$VERSION_ID"

echo
echo "Done. Downloaded files are in: $PWD"
