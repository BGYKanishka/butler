#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-butler.zip>"
    exit 1
fi

ZIP_PATH=$1

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: File not found at $ZIP_PATH"
    exit 1
fi

# We expect sparkle tools to be downloaded to /tmp/sparkle_tools/bin
# If not, prompt the user to download it
if [ ! -f "/tmp/sparkle_tools/bin/sign_update" ]; then
    echo "Sparkle tools not found in /tmp/sparkle_tools"
    echo "Downloading Sparkle tools..."
    mkdir -p /tmp/sparkle_tools
    cd /tmp/sparkle_tools
    curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
    tar -xf sparkle.tar.xz
    cd -
fi

echo "Signing update..."
SIGNATURE_OUTPUT=$(/tmp/sparkle_tools/bin/sign_update "$ZIP_PATH")

ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep 'sparkle:edSignature' | awk -F '"' '{print $2}')
FILE_LENGTH=$(stat -f%z "$ZIP_PATH")

echo ""
echo "=========================================="
echo "Update successfully signed!"
echo "Please add the following XML to your appcast.xml within the <item> tag for this release:"
echo "=========================================="
echo "<item>"
echo "    <title>Version X.Y.Z</title>"
echo "    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
echo "    <sparkle:version>X.Y.Z</sparkle:version>"
echo "    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>"
echo "    <pubDate>$(LC_TIME=en_US date +"%a, %d %b %Y %T %z")</pubDate>"
echo "    <enclosure url=\"https://github.com/BGYKanishka/butler/releases/download/vX.Y.Z/butler.zip\""
echo "               sparkle:edSignature=\"$ED_SIGNATURE\""
echo "               length=\"$FILE_LENGTH\""
echo "               type=\"application/octet-stream\"/>"
echo "</item>"
echo "=========================================="
echo "Don't forget to upload $ZIP_PATH to your GitHub Release!"
