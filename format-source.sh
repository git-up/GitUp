#!/bin/sh -ex

# brew install clang-format

CLANG_FORMAT_VERSION=`clang-format -version | awk '{ print $3 }'`
if [[ "$CLANG_FORMAT_VERSION" != "8.0.0" ]]; then
  echo "Unsupported clang-format version"
  exit 1
fi

find "GitUpKit/Components" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUpKit/Core" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUpKit/Extensions" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUpKit/Interface" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUpKit/Utilities" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUpKit/Views" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i

find "GitUp/Application" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i
find "GitUp/Tool" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i

find "Examples" -type f -iname *.h -o  -iname *.m | xargs clang-format -style=file -i

echo "Done!"
