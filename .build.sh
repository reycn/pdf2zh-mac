# /bin/bash
# This script is used to build the project using Swift Package Manager.
rm -rf ./build
mkdir -p ./Release
swift bundler bundle -o ./Release -c release -u
# zip when the build is successful
if [ $? -eq 0 ]; then
    echo "Build successful, zipping the release..."
    zip -r ./Release/PDFMathTranslate.app.zip ./Release/PDFMathTranslate.app
    echo "Release zipped successfully."
else
    echo "Build failed."
fi