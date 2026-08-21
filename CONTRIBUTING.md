# Contributing

Thanks for helping improve Race Circuit.

## Before opening a change

- Search existing issues before creating a new one.
- Keep changes focused and describe the user-visible behavior they affect.
- Do not commit developer keys, credentials, generated PRG files, personal
  workout data, or screenshots containing identifying information.
- By contributing, you agree that your contribution is licensed under the MIT
  License included with this repository.

## Local development

1. Install the Garmin Connect IQ SDK Manager and a Java runtime supported by
   the active SDK.
2. Install the device package for the watch you want to test.
3. Generate your own local Connect IQ developer key.
4. Run `./build.ps1` in PowerShell for the default Venu 3 build.
5. Test interaction changes in the Connect IQ simulator and, where possible,
   on a physical watch.

The local developer key and generated files are ignored by Git.

## Pull requests

Explain what changed, how it was tested, and which watch models were covered.
Include screenshots only when they contain no account details, local paths, or
other identifying information.
