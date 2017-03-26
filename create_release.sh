#!/bin/bash
VERSION=`awk '/^const STRING =/ { gsub(/"/, ""); print $4}' go/src/github.com/xing/beetle/version.go`
TAG="v$VERSION"
BASEURL="https://source.xing.com/api/v3/repos/architects/gobeetle"
if test -z "$SOURCE_XING_COM_USER"; then
    echo please set environment variable SOURCE_XING_COM_USER
    exit 1
fi
if test -z "$SOURCE_XING_COM_API_TOKEN"; then
    echo please set environment variable SOURCE_XING_COM_API_TOKEN
    exit 1
fi
AUTHENTICATION="--basic --user $SOURCE_XING_COM_USER:$SOURCE_XING_COM_API_TOKEN"

read -r -d '' DESC <<EOF
Downloads:\n\`curl -L https://source.xing.com/architects/gobeetle/releases/download/$TAG/linux.tar.gz\`\n\`curl -L https://source.xing.com/architects/gobeetle/releases/download/$TAG/darwin.tar.gz\`
EOF

read -r -d '' POST_DATA <<EOF
{
  "tag_name": "$TAG",
  "target_commitish": "master",
  "name": "$TAG",
  "body": "$DESC",
  "draft": false,
  "prerelease": true
}
EOF

read -r -d '' PATCH_DATA <<EOF
{
  "body": "$DESC",
  "draft": false,
  "prerelease": true
}
EOF

function get_release() {
    JSON=$(curl -s $BASEURL/releases/tags/$TAG)
    # echo "==========" $JSON
    ID=$(echo $JSON | awk '{for(i=1;i<=NF;i++){ if($i=="\"id\":"){ gsub(",", ""); print $(i+1)} } }' | head -1)
    # echo "----------" $ID
}

function verify_ID() {
    # verify we got the right id
    JSON2=$(curl -s $BASEURL/releases/$ID)
    if [ "$JSON" != "$JSON2" ]; then
        echo "release id $ID could bot be verified"
        exit 1
    fi
}

get_release
if test -z "$ID"; then
    RESPONSE=$(curl -s $AUTHENTICATION -H 'Accept: application/vnd.github.v3+json' -d "$POST_DATA" $BASEURL/releases)
    if [ $? != 0 ]; then
        echo "could not create release"
        exit 1
    fi
    get_release
    verify_ID
else
    verify_ID
    # update the release
    RESPONSE=$(curl -s $AUTHENTICATION -H 'Accept: application/vnd.github.v3+json' -XPATCH -d "$PATCH_DATA" $BASEURL/releases/$ID)
    if [ $? != 0 ]; then
        echo "could not update release"
        exit 1
    fi
fi

UPLOAD_URL=$(echo $JSON | awk '{for(i=1;i<=NF;i++){ if($i=="\"upload_url\":"){ gsub(/[",]/, ""); gsub(/[\{][?]namelabel[\}]/, ""); print $(i+1); } } }')
echo uploading linux binaries using $UPLOAD_URL
RESPONSE=$(curl -s $AUTHENTICATION -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/gzip' --data-binary @release/linux.tar.gz ${UPLOAD_URL}?name=linux.tar.gz)
if [ $? != 0 ]; then
    echo "could not upload linux binaries (maybe the attachment already exists)"
    exit 1
fi
echo uploading darwin binaries using $UPLOAD_URL
RESPONSE=$(curl -s $AUTHENTICATION -H 'Accept: application/vnd.github.v3+json' -H 'Content-Type: application/gzip' --data-binary @release/darwin.tar.gz ${UPLOAD_URL}?name=darwin.tar.gz)
if [ $? != 0 ]; then
    echo "could not upload darwin binaries (maybe the attachment already exists)"
    exit 1
fi
