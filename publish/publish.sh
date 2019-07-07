#!/usr/bin/env bash

# Collect $1 for branch name.
# If null; default to dev.
# If release; set is_release=true
build_branch="${1:-dev}"
echo "mycroft-core branch set to ${build_branch}"
if [[ ${build_branch} == "release" ]]; then
	is_release=true
fi

# Collect $2 for --no-clean arg
if [[ $2 == "--no-clean" ]]; then
	echo "--no-clean flag is set"
	no_clean=true
fi

# Function to check for is_release for use elsewhere
function is_release () {
	if [ "${is_release}" = true ]; then
		echo "Setting is_release to true"
		return 0
	else
		return 1
	fi
}

set -Ee

TOP=$(cd $(dirname $0)/.. && pwd -L)
MYCROFT_CORE_SRC=${TOP}/src/mycroft-core


function _run() {
  if [[ "$QUIET" ]]; then
    echo "$*"
  else
    eval "$@"
  fi
}

function core_version() {
    basename $(git for-each-ref --format="%(refname:short)" --sort=-authordate --count=1 refs/tags) | sed -e 's/v//g'
}

# If the --no-clean flag is not set, then remove the previous source checkout and clone
if [ "${no_clean}" != true ]; then
	# clean
	cd ${TOP}
	rm -Rf ${TOP}/src
	mkdir -p ${TOP}/src
	cd ${TOP}/src
	rm -rf ${MYCROFT_CORE_SRC}/dist
	# Clone mycroft-core
        if is_release; then
		git clone https://github.com/MycroftAi/mycroft-core.git
	else
		# Clone the dev branch
		git clone --depth=1 --branch=${build_branch} https://github.com/MycroftAi/mycroft-core.git
		# Fetch release tags so the version can be determined
		cd mycroft-core
		# fetch only the tags/release/* tags
		git fetch --depth=1 origin refs/tags/release/*:refs/tags/release/*
		cd ${TOP}/src
	fi
else
	cd ${TOP}/src
fi


# Enter the source directory
cd mycroft-core

# Use is_release to determine if we clone a branch or latest release; set version format
if is_release; then
	# Set version to the latest release tag
	# checkout the latest release tag
	VERSION="$(core_version)"
	git checkout release/v${VERSION}
        RELEASE_TYPE="release"
        DISTRIBUTION_TYPE="stable"
else
	# fetch all branches
	git fetch
	# checkout ${build_branch}
	git checkout ${build_branch}
	# use a Latest version + timestamp as the version
	VERSION="$(core_version)+$(date +%s)"
        RELEASE_TYPE="daily"
        DISTRIBUTION_TYPE="unstable"
fi

echo "version=\"${VERSION}\"" > ${MYCROFT_CORE_SRC}/mycroft/__version__.py

# build distributable virtualenv
ARCH="$(dpkg --print-architecture)"


# package distributable virtualenv into deb
function replace() {
  local FILE=$1
  local PATTERN=$2
  local VALUE=$3
  local TMP_FILE="/tmp/$$.replace"
  cat ${FILE} | sed -e "s/${PATTERN}/${VALUE}/g" > ${TMP_FILE}
  mv ${TMP_FILE} ${FILE}
}

PYTHON_VERSION=$( python3 -c 'from sys import version_info as vi;print("python{0}.{1}".format(*vi))' )
echo "Will be creating package with ${PYTHON_VERSION}"

DEB_BASE="mycroft-core-${ARCH}_${VERSION}-1"
DEB_DIR=${MYCROFT_CORE_SRC}
mkdir -p ${DEB_DIR}/debian
mkdir -p ${DEB_DIR}/inits

echo "Setting latest compatibility"
echo "9" > ${MYCROFT_CORE_SRC}/debian/compat

echo "Adding hourly cronjob"
#cp ${TOP}/publish/deb_base/mycroft-core.cron.hourly ${DEB_DIR}/debian

cp -r ${TOP}/publish/deb_base/bins ${DEB_DIR}/
#cp ${DEB_DIR}/scripts/mycroft-use.sh ${DEB_DIR}/bins/mycroft-use
cp ${TOP}/publish/deb_base/install ${DEB_DIR}/debian
cp ${TOP}/publish/deb_base/mycroft-core.links ${DEB_DIR}/debian
#cp ${TOP}/publish/deb_base/mycroft-core.logrotate ${DEB_DIR}/debian

echo "Creating debian control file"
# setup control file
CONTROL_FILE=${DEB_DIR}/debian/control
cp ${TOP}/publish/deb_base/control.template ${CONTROL_FILE}
replace ${CONTROL_FILE} "%%PACKAGE%%" "mycroft-core"
replace ${CONTROL_FILE} "%%ARCHITECTURE%%" "${ARCH}"
replace ${CONTROL_FILE} "%%DESCRIPTION%%" "mycroft-core"
replace ${CONTROL_FILE} "%%DEPENDS%%" "perl, jq, portaudio19-dev, libglib2.0-0, flac, mpg123, pulseaudio, git, python3-dev, libjpeg-dev, libfann-dev (>= 2.2.0), packagekit, mimic (>= 1.2.0)"

# Create trigger to handle updated python
touch ${DEB_DIR}/debian/mycroft-core.triggers

echo "Creating rules file..."
RULES_FILE=${DEB_DIR}/debian/rules
cp ${TOP}/publish/deb_base/rules ${RULES_FILE}
#Help debian helper finding the PIL libraries
replace ${RULES_FILE} "%%DEB_DIR%%" $( echo ${DEB_DIR} | sed 's_/_\\/_g' )
replace ${RULES_FILE} "%%PYTHON_DIR%%" ${PYTHON_VERSION}

echo "Creating changelog..."
CHANGELOG_FILE=${DEB_DIR}/debian/changelog
cp ${TOP}/publish/deb_base/changelog ${CHANGELOG_FILE}
replace ${CHANGELOG_FILE} "%%VERSION%%" "${VERSION}"
replace ${CHANGELOG_FILE} "%%TYPE%%" "${DISTRIBUTION_TYPE}"

echo "Creating debian preinst file"
PREINST_FILE=${DEB_DIR}/debian/preinst
cp ${TOP}/publish/deb_base/preinst.template ${PREINST_FILE}
replace ${PREINST_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${PREINST_FILE}

echo "Creating debian postinst file"
POSTINST_FILE=${DEB_DIR}/debian/postinst
cp ${TOP}/publish/deb_base/postinst.template ${POSTINST_FILE}
replace ${POSTINST_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${POSTINST_FILE}

echo "Creating debian prerm file"
PRERM_FILE=${DEB_DIR}/debian/prerm
cp ${TOP}/publish/deb_base/prerm.template ${PRERM_FILE}
replace ${PRERM_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${PRERM_FILE}

echo "Creating debian postrm file"
POSTRM_FILE=${DEB_DIR}/debian/postrm
cp ${TOP}/publish/deb_base/postrm.template ${POSTRM_FILE}
replace ${POSTRM_FILE} "%%INSTALL_USER%%" "mycroft"
chmod 0755 ${POSTRM_FILE}

VENV_BIN="/opt/venvs/mycroft-core/bin"

# setup init scripts
function setup_init_script() {
  local NAME=$1
  local LOG_NAME=$2
  echo "Creating init script for ${NAME}"
  INIT_SCRIPT=${DEB_DIR}/inits/${NAME}
  mkdir -p $(dirname ${INIT_SCRIPT})
  cp ${TOP}/publish/deb_base/init.template ${INIT_SCRIPT}
  replace ${INIT_SCRIPT} "%%NAME%%" "${NAME}"
  replace ${INIT_SCRIPT} "%%LOG_NAME%%" "${LOG_NAME}"
  replace ${INIT_SCRIPT} "%%DESCRIPTION%%" "${NAME}"
  replace ${INIT_SCRIPT} "%%COMMAND%%" "$( echo ${VENV_BIN}/${NAME}  | sed 's_/_\\/_g' )"
  replace ${INIT_SCRIPT} "%%USERNAME%%" "mycroft"
  chmod a+x ${INIT_SCRIPT}
}


# setup init scripts
function setup_init_script_speech() {
  local NAME=$1
  local LOG_NAME=$2
  echo "Creating init script for ${NAME}"
  INIT_SCRIPT=${DEB_DIR}/inits/${NAME}
  mkdir -p $(dirname ${INIT_SCRIPT})
  cp ${TOP}/publish/deb_base/init.speech.template ${INIT_SCRIPT}
  replace ${INIT_SCRIPT} "%%NAME%%" "${NAME}"
  replace ${INIT_SCRIPT} "%%LOG_NAME%%" "${LOG_NAME}"
  replace ${INIT_SCRIPT} "%%DESCRIPTION%%" "${NAME}"
  replace ${INIT_SCRIPT} "%%COMMAND%%" "$( echo ${VENV_BIN}/${NAME}  | sed 's_/_\\/_g' )"
  replace ${INIT_SCRIPT} "%%USERNAME%%" "mycroft"
  chmod a+x ${INIT_SCRIPT}
}

if [ ${ARCH} = "armhf" ]; then
  echo "Setting up enclosure"
  setup_init_script_enclosure "mycroft-enclosure-client" "enclosure"
  echo "inits/mycroft-enclosure-client etc/init.d" >> ${DEB_DIR}/debian/install

  echo "Setting up sudo privileges"
  cp -r ${TOP}/publish/sudoers ${DEB_DIR}/
  echo "sudoers/013_mycroft-pip etc/sudoers.d/" >> ${DEB_DIR}/debian/install
  #echo "sudoers/014_mycroft-dpkg /etc/sudoers.d/" >> ${DEB_DIR}/debian/install
  echo "Adding mycroft-use to installation"
  cp ${DEB_DIR}/scripts/mycroft-use.sh ${DEB_DIR}/bins/mycroft-use
  chmod +x ${DEB_DIR}/bins/mycroft-use
  echo "bins/mycroft-use /usr/bin" >> ${DEB_DIR}/debian/install
else
  echo "Setting up sudo privileges"
  cp -r ${TOP}/publish/sudoers ${DEB_DIR}/
  echo "sudoers/013_mycroft-pip etc/sudoers.d/" >> ${DEB_DIR}/debian/install
  cp ${TOP}/publish/deb_base/mycroft.conf ${DEB_DIR}
  echo "mycroft.conf etc/mycroft/" >> ${DEB_DIR}/debian/install
fi

#echo "Setting up polkit power permissions file"
#cp -r ${TOP}/publish/polkit ${DEB_DIR}/
#POLKIT_TARGET=/etc/polkit-1/localauthority/50-local.d/
#echo "polkit/allow_user_to_shutdown_reboot.pkla $POLKIT_TARGET" >> ${DEB_DIR}/debian/install
#echo "polkit/allow_mycroft_to_install_package.pkla $POLKIT_TARGET" >> ${DEB_DIR}/debian/install

cd ${DEB_DIR}
dpkg-buildpackage -us -uc

cd ${TOP}/src
mv mycroft-core_${VERSION}_${ARCH}.deb ../mycroft-core-${ARCH}_${VERSION}-1.deb

