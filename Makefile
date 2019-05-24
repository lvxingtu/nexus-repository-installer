APP = nexus-repository-manager

# The app version (as bundled and published to RSO)
#VERSION ?= 3.15.2-01
VERSION ?= 3.16.1-02

# the name of the original bundle file
#BUNDLE_FILE := $(APP)-$(VERSION)-unix.tar.gz
BUNDLE_FILE := nexus-$(VERSION)-unix.tar.gz

FETCH_URL ?= "http://download.sonatype.com/nexus/3/$(BUNDLE_FILE)"

RHEL_VERSION ?= 7
# The release of the RPM package
PKG_RELEASE ?= 1.el$(RHEL_VERSION)

# The version to assign to the RPM package
PKG_VERSION := $(shell echo $(VERSION) | sed -e 's|-|_|')

BASEDIR=$(CURDIR)
BUILDDIR ?= $(BASEDIR)/build

RPMDIR := $(BUILDDIR)/rpmbuild

RPM_NAME := $(APP)-$(PKG_VERSION)-$(PKG_RELEASE).noarch.rpm

# create lists of patchfiles and where to install them
patchfiles := $(wildcard patches/*)
dest_patchfiles := $(patsubst patches/%.patch,$(RPMDIR)/SOURCES/$(APP)-$(PKG_VERSION)-%.patch,$(patchfiles))

# rpmbuild subdirectories
rpm_subdirs := $(addprefix $(RPMDIR)/,BUILD SRPMS RPMS SPECS SOURCES)

help:
	@echo 'Usage:                                                 '
	@echo '  make fetch              retrieve bundle from RSO     '
	@echo '  make populate           `fetch`; populate rpmbuild tree with sources and patches'
	@echo '  make docker             use a docker container to build the RPM'
	@echo '  make show-version       displays version to be built '
	@echo '  make show-release       displays release to be built '
	@echo '  make clean              remove generated files       '

clean:
	rm -rf $(BUILDDIR)/*

show-version:
	@echo $(VERSION)

show-release:
	@echo $(PKG_RELEASE)

fetch: $(BUILDDIR) $(BUILDDIR)/$(BUNDLE_FILE)

#populate: fetch $(rpm_subdirs) $(RPMDIR)/SOURCES/$(APP)-$(PKG_VERSION)-rpm.tar.gz $(dest_patchfiles) $(RPMDIR)/SOURCES/$(BUNDLE_FILE) $(RPMDIR)/SPECS/$(APP).spec
populate: fetch $(rpm_subdirs) $(dest_patchfiles) $(RPMDIR)/SOURCES/$(BUNDLE_FILE) $(RPMDIR)/SPECS/$(APP).spec

rpm: populate $(RPMDIR)/RPMS/noarch/$(RPM_NAME)

rpm-clean:
	rm -rf $(RPMDIR)

build: rpm $(BUILDDIR)/$(RPM_NAME)


# retrieve the original bundle from FETCH_URL
$(BUILDDIR)/$(BUNDLE_FILE):
	@ echo "fetching bundle from $(FETCH_URL)"
	@ curl -s -L -k -f -o $@ $(FETCH_URL)

# create RPM subdirectories
$(rpm_subdirs):
	mkdir -p $@

# create Source2 tarball (./extra)
#$(RPMDIR)/SOURCES/$(APP)-$(PKG_VERSION)-rpm.tar.gz:
#	tar -cz --exclude .gitignore -f $@ extra

# create Source tarball
$(RPMDIR)/SOURCES/$(APP)-$(PKG_VERSION)-rpm.tar.gz:
	/bin/ls -alhR
	tar -cz --exclude .gitignore -f $@

# copy patches to SOURCES
$(RPMDIR)/SOURCES/$(APP)-$(PKG_VERSION)-%.patch: patches/%.patch
	cp $< $@

# copy original bundle to SOURCES
$(RPMDIR)/SOURCES/$(BUNDLE_FILE):
	cp $(BUILDDIR)/$(BUNDLE_FILE) $@

# create the SPEC file from template
$(RPMDIR)/SPECS/$(APP).spec: $(APP).spec
	sed \
	-e "s|%%RELEASE%%|$(PKG_RELEASE)|" \
	-e "s|%%VERSION%%|$(PKG_VERSION)|" \
	-e "s|%%BUNDLE_FILE%%|$(BUNDLE_FILE)|" \
	$(APP).spec > $@

# create the rpm
$(RPMDIR)/RPMS/noarch/$(RPM_NAME):
	rpmbuild --define '_topdir $(RPMDIR)' -bb $(RPMDIR)/SPECS/$(APP).spec

# copy the build RPM to final location
$(BUILDDIR)/$(RPM_NAME): $(RPMDIR)/RPMS/noarch/$(RPM_NAME)
	cp $< $@


# dockerize
docker: docker-clean
	docker build --tag $(APP)-rpm:$(RHEL_VERSION) .
	docker run --name $(APP)-rpm-$(RHEL_VERSION)-data $(APP)-rpm:$(RHEL_VERSION) echo "data only container"
	docker run --volumes-from $(APP)-rpm-$(RHEL_VERSION)-data --rm \
		-e PKG_RELEASE=$(PKG_RELEASE) -e VERSION=$(VERSION) \
                -e RHEL_VERSION=$(RHEL_VERSION) \
		$(APP)-rpm:$(RHEL_VERSION) make build
	docker run --volumes-from $(APP)-rpm-$(RHEL_VERSION)-data --rm \
		-v /tmp:/host:rw \
		$(APP)-rpm:$(RHEL_VERSION) cp /data/build/$(RPM_NAME) /host/
	@ cp /tmp/$(RPM_NAME) build/
	@ docker rm $(APP)-rpm-$(RHEL_VERSION)-data 2>&1 >/dev/null

docker-clean:
	docker inspect $(APP)-rpm-$(RHEL_VERSION)-data >/dev/null 2>&1 && \
		docker rm $(APP)-rpm-$(RHEL_VERSION)-data || \
		true

.PHONY: help clean fetch populate rpm build docker docker-clean
