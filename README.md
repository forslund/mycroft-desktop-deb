# mycroft-packaging
Scripts for creating distributable debian packages for Mycroft. The script uses debhelper and dh-virtualenv to create a virtualenv installation where mycroft can modify the python modules without the risks of modifying the host environment.

# Setup
Run the dependencies.sh script to install the prerequisite packages for the build.

# Building mycroft core, using default "dev" branch
./publish/publish.sh
# Using specified branch
./publish/publish.sh feature/some-branch-to-test
# Build a branch without cleaning and re-cloning the source code
./publish/publish.sh feature/some-branch-to-test --no-clean
# Building a release version
./publish/publish.sh release

# Building in docker
To make building for different distributions easier a couple of example dockerfiles are included.

To build a docker container for the build copy the appropriate container to the root of the repo

```sh
cp docker/Dockerfile.disco Dockerfile
```

then build the docker container

```sh
docker build . -t desktop-package-builder-disco
```

after that you can run the image to build the package. To retrieve the package you need to specify a /host volume, for example:

```sh
docker run -v "`pwd`/debs:/host" -it desktop-package-builder-disco
```
