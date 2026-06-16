cd "${LOVE_SOURCE_DIR}"

zip -9 -r "../${LOVE_FILE}" . \
  -x "*.git*" \
  -x "*.DS_Store"

cd ..