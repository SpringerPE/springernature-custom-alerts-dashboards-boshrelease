#!/usr/bin/env bash
# set -o pipefail  # exit if pipe command fails
[ -z "$DEBUG" ] || set -x
set -e

##

RELEASE="springernature-custom-alerts-dashboards"
DESCRIPTION="Bosh release add-on for prometheus-boshrelease to add custom resources: alerts, dashboards, etc"
GITHUB_REPO="SpringerPE/springernature-custom-alerts-dashboards-boshrelease"

###

BOSH_CLI=${BOSH_CLI:-bosh}
S3CMD=${S3CMD:-s3cmd}
JQ=jq
CURL="curl -s"
SHA1="sha1sum -b"
RE_VERSION_NUMBER='^[0-9]+([0-9\.]*[0-9]+)*$'

# Create a personal github token to use this script
if [ -z "$GITHUB_TOKEN" ]
then
    echo "Github TOKEN not defined!"
    echo "See https://help.github.com/articles/creating-an-access-token-for-command-line-use/"
    exit 1
fi

# You need bosh installed and with you credentials
if ! [ -x "$(command -v $BOSH_CLI)" ]
then
    echo "ERROR: $BOSH_CLI command not found! Please install it and make it available in the PATH"
    exit 1
fi

# You need jq installed
if ! [ -x "$(command -v $JQ)" ]
then
    echo "ERROR: $JQ command not found! Please install it and make it available in the PATH"
    exit 1
fi

# You need sha1sum installed  (brew md5sha1sum)
if ! [ -x "$(command -v $SHA1)" ]
then
    echo "ERROR: $SHA1 command not found! Please install it and make it available in the PATH"
    exit 1
fi

case $# in
    0)
        echo "*** Creating a new release. Automatically calculating next release version number"
        ;;
    1)
        if [ $1 == "-h" ] || [ $1 == "--help" ]
        then
            echo "Usage:  $0 [version-number]"
            echo "  Creates a new boshrelease, commits the changes to this repository using tags and uploads "
            echo "  the release to Github releases. It also adds comments based on previous git commits and "
            echo "  calculates the sha1 checksum."
            exit 0
        else
            version=$1
            if ! [[ $version =~ $RE_VERSION_NUMBER ]]
            then
                echo "ERROR: Incorrect version number!"
                exit 1
            fi
            echo "*** Creating a new release. Using release version number $version."
        fi
        ;;
    *)
        echo "ERROR: incorrect argument. See '$0 --help'"
        exit 1
        ;;
esac


# Get the last git commit made by this script
lastcommit=$(git log --format="%h" --grep="$RELEASE v*" | head -1)
echo "* Changes since last version with commit $lastcommit: "
git_changes=$(git log --pretty="%h %aI %s (%an)" $lastcommit..@ | sed 's/^/- /')
if [ -z "$git_changes" ]
then
    echo "Error, no commits since last release with commit $lastcommit!. Please "
    echo "commit your changes to create and publish a new release!"
    exit 1
fi
echo "$git_changes"

# Uploading blobs
echo "* Uploading blobs to the blobstore ..."
$BOSH_CLI upload-blobs

# Creating the release
if [ -z "$version" ]
then
    echo "* Creating final release ..."
    $BOSH_CLI create-release --force --final --tarball="/tmp/$RELEASE-$$.tgz" --name "$RELEASE"
    # Get the version of the release
    version=$(ls releases/$RELEASE/$RELEASE-*.yml | sed 's/.*\/.*-\(.*\)\.yml$/\1/' | sort -t. -k 1,1nr -k 2,2nr | head -1)
else
    echo "* Creating final release version $version ..."
    $BOSH_CLI create-release --force --final --tarball="/tmp/$RELEASE-$$.tgz" --name "$RELEASE" --version "$version"
fi

# Create a new tag and update the changes
echo "* Commiting git changes ..."
git add .final_builds releases/$RELEASE/index.yml "releases/$RELEASE/$RELEASE-$version.yml" blobstore
git commit -m "$RELEASE v$version Boshrelease"
git push
git push --tags

# Create a release in Github
echo "* Creating a new release in Github ... "
sha1=$($SHA1 "/tmp/$RELEASE-$$.tgz" | cut -d' ' -f1)
description=$(cat <<EOF
# $RELEASE version $version

$DESCRIPTION

## Changes since last version

$git_changes

## Using in a bosh Deployment

    releases:
    - name: $RELEASE
      url: https://github.com/${GITHUB_REPO}/releases/download/v${version}/${RELEASE}-${version}.tgz
      version: $version
      sha1: $sha1
EOF
)
printf -v DATA '{"tag_name": "v%s","target_commitish": "master","name": "v%s","body": %s,"draft": false, "prerelease": false}' "$version" "$version" "$(echo "$description" | $JQ -R -s '@text')"
releaseid=$($CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -XPOST --data "$DATA" "https://api.github.com/repos/$GITHUB_REPO/releases" | $JQ '.id')

# Upload the release
echo "* Uploading tarball to Github releases section ... "
echo -n "  URL: "
$CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"/tmp/$RELEASE-$$.tgz" "https://uploads.github.com/repos/$GITHUB_REPO/releases/$releaseid/assets?name=$RELEASE-$version.tgz" | $JQ -r '.browser_download_url'

# Delete the release
rm -f "/tmp/$RELEASE-$$.tgz"

echo
echo "*** Description https://github.com/$GITHUB_REPO/releases/tag/v$version: "
echo
echo "$description"
exit 0
