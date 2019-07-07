# mycroft-packaging
Scripts for creating distributable packages for Mycroft. The script uses debhelper and mh-virtualenv to create a virtualenv installation where mycroft can modify the python modules without the risks of modifying the host environment.

# Building mycroft core, using default "dev" branch
./mycroft-core-deb/publish/publish.sh
# Using specified branch
./mycroft-core-deb/publish/publish.sh feature/some-branch-to-test
# Build a branch without cleaning and re-cloning the source code
./mycroft-core-deb/publish/publish.sh feature/some-branch-to-test --no-clean
# Building a release version
./mycroft-core-deb/publish/publish.sh release
