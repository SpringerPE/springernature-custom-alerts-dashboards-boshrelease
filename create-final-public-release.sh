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
    echo "$BOSH_CLI command not found!";
    exit 1
fi

# You need jq installed
if ! [ -x "$(command -v $JQ)" ]
then
    echo "$JQ command not found!";
    exit 1
fi

#Uploading blobs
echo "* Uploading blobs to the blobstore ..."
$BOSH_CLI upload-blobs

# Creating the release
echo "* Creating final release ..."
$BOSH_CLI create-release --force --final --tarball=/tmp/$RELEASE-$$.tgz --name $RELEASE

# Get the version of the release
version=$(ls -r -v releases/$RELEASE/$RELEASE-*.yml | sed 's/.*\/.*-\(.*\)\.yml$/\1/' | head -1)

# Create a new tag and update the changes
echo "* Commiting git changes ..."
git add .final_builds releases/$RELEASE/index.yml "releases/$RELEASE/$RELEASE-$version.yml" blobstore
git commit -m "$RELEASE v$version Boshrelease"
git push --tags

# Create a release in Github
echo "* Creating a new release in Github ... "
description="$DESCRIPTION version $version <br><br>sha1: $($SHA1 /tmp/$RELEASE-$$.tgz | cut -d' ' -f1)"
printf -v DATA '{"tag_name": "v%s","target_commitish": "master","name": "v%s","body": "%s","draft": false, "prerelease": false}' "$version" "$version" "$description"
releaseid=$($CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -XPOST --data "$DATA" "https://api.github.com/repos/$GITHUB_REPO/releases" | $JQ '.id')

# Upload the release
echo "* Uploading tarball to Github releases section ... "
echo -n "  URL: "
$CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"/tmp/$RELEASE-$$.tgz" "https://uploads.github.com/repos/$GITHUB_REPO/releases/$releaseid/assets?name=$RELEASE-$version.tgz" | $JQ -r '.browser_download_url'

# Delete the release
rm -f /tmp/$RELEASE-$$.tgz
