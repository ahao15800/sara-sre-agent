#!/bin/bash
ZIP_NAME="sara_sre_agent_resukisu_v1.0.0.zip"
rm -f "$ZIP_NAME"
# Note: Use local zip tool if available
zip -r "$ZIP_NAME" . -x "*.git*" "build_zip.sh" "*.zip"
echo "Build complete: $ZIP_NAME"
