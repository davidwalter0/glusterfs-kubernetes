ifndef BUILD_SETUP
$(info BUILD_SETUP not set, run from the ./build command which sets the environment)
$(info You can configure the environment with the container versions in the environment file)
$(error Unconfigured environment or running with make not the build script)
endif



all:										\
	server/built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}	\
	client/built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}	\
	server/all-in-one.yaml

.server: environment Makefile server/build server/Dockerfile.tmpl
	make -C server -f ../Makefile bld-server
.client: environment Makefile client/build client/Dockerfile.tmpl
	make -C client -f ../Makefile bld-client

bld-server:
	@echo Building $@
	./build
	touch built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}
	@echo Complete $@

bld-client:
	@echo Building $@
	./build
	touch built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}
	@echo Complete $@

client/built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}: .client
	touch $@ $<

server/built.debian.${DEBIAN_RELEASE}.glusterfs.${GLUSTERFS_VERSION}: .server
	touch $@ $<

server/all-in-one.yaml: server/all-in-one.yaml.tmpl
	applytmpl < $< > $@
