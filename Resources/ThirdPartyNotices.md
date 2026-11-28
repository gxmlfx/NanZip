# Third-Party Notices

NanZip bundles the console executable `7zz` from 7-Zip.

- Project: https://github.com/ip7z/7zip
- Official download: https://www.7-zip.org/download.html
- License information: https://www.7-zip.org/license.txt
- Installed local development build in this environment: Homebrew formula `sevenzip` 26.06

7-Zip is Copyright (c) Igor Pavlov and contributors. See the upstream license for the exact terms governing the bundled executable and source code.

The app does not link against macOS system `libarchive`; archive operations are executed through the bundled 7-Zip process.
