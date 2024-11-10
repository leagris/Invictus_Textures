#!/usr/bin/env sh

set -x

main() {
  packVersion=${TRAVIS_TAG:-$(git describe --tags)}

  [ -z "$packVersion" ] && return 1
  packFormat=${packVersion%%.*}

  baseDir=$(cd "${0%/*}" && pwd)
  buildDir=$baseDir/build
  buildResourcesDir=$buildDir/resources
  archiveDir=$buildDir/archives
  srcResources=$baseDir/src/main/resources
  suffix=-$packVersion
  displayName=Invictus$suffix
  releaseFile=$archiveDir/$displayName.zip

  case "$1" in
  build) build ;;
  clean) clean ;;
  publish) publish ;;
  *) publish ;;
  esac
}

copyResources() {
  clean
  mkdir -p "$buildResourcesDir"
  cp -r "$srcResources" "$buildResourcesDir" &&
   cp "$baseDir/LICENSE" "$baseDir/LICENSE_CC_BY_NC_SA.md" "$baseDir/README.md" "$buildResourcesDir"
}

updatePackMcmeta() {
  jq --argjson packFormat "$packFormat" \
  '.pack.pack_format = $packFormat' \
  "$srcResources/pack.mcmeta" > "$buildResourcesDir/pack.mcmeta"
  exit
}

zipArchive() {
  mkdir -p "$archiveDir"
  rm -f "$releaseFile"
  case "$-" in *x*) q= ;; *) q=-q ;; esac
  cd "$buildResourcesDir" || return 1
  zip ${q:+"$q"} -r9 "$releaseFile" . -x '__MACOSX' -x '\.*'
  rc=$?
  cd "$baseDir" || return 1
  zip ${q:+"$q"} -9 "$releaseFile" LICENSE LICENSE_CC_BY_NC_SA.md README.md
  return $((rc || $?))
}

build() {
  copyResources
  updatePackMcmeta
  zipArchive
}

clean() {
  rm -fr "${baseDir:?}/build"
}

publish() {
  if build && [ -n "$CURSEFORGE_INVICTUS_TOKEN" ]; then

    projectId=220720

    # Many ids are red herrings. Weird to have an API without any documentation.
    versionData=$(CurseForge_gameVersions) || return 1
    #versionData='[{"gameVersionTypeID":70886,"id":42,"slug":"string","name":"1.16"}]'

    # shellcheck disable=SC2016 # Constant expression with $ signs
    case "$packFormat" in
    1) jqs='[.[] | select(((.name | startswith("1.6")) or (.name | startswith("1.7")) or (.name | startswith("1.8"))) and (.gameVersionTypeID==(6, 5, 4))) | .id]' ;;
    2) jqs='[.[] | select(((.name | startswith("1.9")) or (.name | startswith("1.10"))) and (.gameVersionTypeID==(552, 572))) | .id]' ;;
    3) jqs='[.[] | select(((.name | startswith("1.11")) or (.name | startswith("1.12"))) and (.gameVersionTypeID==(599, 628))) | .id]' ;;
    4) jqs='[.[] | select(((.name | startswith("1.13")) or (.name | startswith("1.14"))) and (.gameVersionTypeID==(55023, 64806))) | .id]' ;;
    5) jqs='[.[] | select((.name | startswith("1.15")) and (.gameVersionTypeID==68722)) | .id]' ;;
    6) jqs='[.[] | select((.name | startswith("1.16")) and (.gameVersionTypeID==70886)) | .id]' ;;
    *) return 1 ;;
    esac

    GAME_IDS=$(jq -cn --argjson versionData "$versionData" "\$versionData | $jqs") || return 1

    case "$-" in *x*)
      jq -n \
        --arg changelog 'https://github.com/InvictusGraphics/Invictus_Textures/commits/master' \
        --arg displayName "$displayName" \
        --argjson gameVersions "$GAME_IDS" \
        '{"changelog":$changelog,"changelogType":"text","displayName":$displayName,"gameVersions":$gameVersions,"releaseType":"release"}' >&2
      ;;
    esac

    jq -c -n \
      --arg changelog 'https://github.com/InvictusGraphics/Invictus_Textures/commits/master' \
      --arg displayName "$displayName" \
      --argjson gameVersions "$GAME_IDS" \
      '{"changelog":$changelog,"changelogType":"text","displayName":$displayName,"gameVersions":$gameVersions,"releaseType":"release"}' |
      CurseForge_uploadFile "$projectId" "$releaseFile"
  fi
}

## CurseForge API
CURSE_FORGE_API=https://minecraft.curseforge.com/api
CURSE_FORGE_API_TOKEN=${CURSEFORGE_INVICTUS_TOKEN}

# Uploads a file to CurseForge API
# @params
# $1: The project ID
# $2: The path to the file to upload
# @streams
# <: the JSON metadata
CurseForge_uploadFile() {
  curl -X POST -H "X-Api-Token: ${CURSE_FORGE_API_TOKEN:?}" -F metadata=@- \
    -F "file=@${2:?}" "$CURSE_FORGE_API/projects/${1:?}/upload-file"
}

# Retrieves game versions
CurseForge_gameVersions() {
  curl -X GET "$CURSE_FORGE_API/game/versions" -H "X-Api-Token: ${CURSE_FORGE_API_TOKEN:?}"
}

main "$@"
