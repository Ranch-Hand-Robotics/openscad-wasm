ENV ::= release
PTHREAD ::= 0
BUILDKIT ::= 0
EMSCRIPTEN_FLAGS := -fexceptions
DOCKER_EXTRA_ARGS :=

ifeq ($(strip $(ENV)),debug)
		CMAKE_BUILD_TYPE := Debug
		MESON_BUILD_TYPE := debug
		EMSCRIPTEN_FLAGS += -g -O0
else ifeq ($(strip $(ENV)),release)
		CMAKE_BUILD_TYPE := Release
		MESON_BUILD_TYPE := release
		EMSCRIPTEN_FLAGS += -O3
else ifeq ($(strip $(ENV)),minsize)
		CMAKE_BUILD_TYPE := MinSizeRel
		MESON_BUILD_TYPE := minsize
		EMSCRIPTEN_FLAGS += -Os
else
		$(error Bad ENV, must be release, minsize or debug)
endif

ifeq ($(PTHREAD),1)
    VARIANT = -pthread
    EMSCRIPTEN_FLAGS += -pthread 
# -sSHARED_MEMORY=1 -sPROXY_TO_PTHREAD=1 -sPTHREAD_POOL_SIZE=4
else
    VARIANT =
endif

DOCKER_TAG_BASE ?= openscad/wasm-base$(VARIANT)-$(ENV)
DOCKER_TAG_OPENSCAD ?= openscad/wasm$(VARIANT)-$(ENV)
DOCKER_OCI_BASE ?= .oci.wasm-base$(VARIANT)-$(ENV)

# Use the arm64 version of the emscripten sdk if running on an arm64 machine, as the amd64 image would crash QEMU in a couple of places.
# See latest version in https://hub.docker.com/r/emscripten/emsdk/tags
EMSCRIPTEN_VERSION ?= 4.0.10
ifeq ($(OS),Windows_NT)
	UNAME_MACHINE := $(PROCESSOR_ARCHITECTURE)
	ifeq ($(UNAME_MACHINE),AMD64)
		UNAME_MACHINE := x86_64
	endif
	ifeq ($(UNAME_MACHINE),ARM64)
		UNAME_MACHINE := arm64
	endif
	TOUCH := type nul >>
	MKDIR_BUILD := if not exist build mkdir build
	MKDIR_LIBS := if not exist libs mkdir libs
	MKDIR_RES_NOTO := if not exist res\noto mkdir res\noto
else
	UNAME_MACHINE := $(shell uname -m)
	TOUCH := touch
	MKDIR_BUILD := mkdir -p build
	MKDIR_LIBS := mkdir -p libs
	MKDIR_RES_NOTO := mkdir -p res/noto
endif
ifeq ($(UNAME_MACHINE),arm64)
    EMSCRIPTEN_SDK_TAG=emscripten/emsdk:$(EMSCRIPTEN_VERSION)-arm64
else
    EMSCRIPTEN_SDK_TAG=emscripten/emsdk:$(EMSCRIPTEN_VERSION)
endif

all: build

.PHONY: wasm
wasm: build

clean:
	rm -rf libs
	rm -rf build
	rm -rf .oci.* .*.make
	rm -rf runtime/dist runtime/node_modules

test:
	cd tests; deno test --allow-read --allow-write

.PHONY: example
example:
	cd example; deno run --allow-net --allow-read server.ts

.PHONY: cli
cli:
	deno run --allow-read --allow-write --allow-env --allow-net cli-init.ts $(ARGS)

.PHONY: release-collateral
release-collateral:
	powershell -ExecutionPolicy Bypass -File scripts\release-collateral.ps1 -Tag $(TAG) $(if $(REPO),-Repo $(REPO),)

.PHONY: upload-release-collateral
upload-release-collateral:
	powershell -ExecutionPolicy Bypass -File scripts\release-collateral.ps1 -Tag $(TAG) $(if $(REPO),-Repo $(REPO),) -CreateRelease -Upload

.PHONY: build
build: build/openscad.wasm.js build/openscad.fonts.js

build/openscad.fonts.js: runtime/node_modules runtime/**/* res
	$(MKDIR_BUILD)
	cd runtime && npm run build
ifeq ($(OS),Windows_NT)
	copy /Y runtime\dist\*.js build\ > nul
	copy /Y runtime\dist\*.d.ts build\ > nul
else
	cp runtime/dist/*.js build/
	cp runtime/dist/*.d.ts build/
endif

runtime/node_modules:
	cd runtime && npm install

build/openscad.wasm.js: .image$(VARIANT)-$(ENV).make
	$(MKDIR_BUILD)
	docker rm -f tmpcpy
	docker run --name tmpcpy $(DOCKER_TAG_OPENSCAD)
	docker cp tmpcpy:/home/build/openscad.js build/openscad.wasm.js || docker cp tmpcpy:/home/ubuntu/build/openscad.js build/openscad.wasm.js
	docker cp tmpcpy:/home/build/openscad.wasm build/ || docker cp tmpcpy:/home/ubuntu/build/openscad.wasm build/
	docker cp tmpcpy:/home/build/openscad.wasm.map build/ || docker cp tmpcpy:/home/ubuntu/build/openscad.wasm.map build/ || echo [*] openscad.wasm.map not found, skipping
	docker rm tmpcpy

#
# Base image with emscripten and all the library dependencies
# for building OpenSCAD WASM.
#
.base-image$(VARIANT)-$(ENV).make: libs Dockerfile.base
ifeq ($(BUILDKIT),0)
	docker build libs \
		$(DOCKER_EXTRA_ARGS) \
		-f Dockerfile.base \
		-t $(DOCKER_TAG_BASE) \
		--build-arg "CMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)" \
		--build-arg "MESON_BUILD_TYPE=$(MESON_BUILD_TYPE)" \
		--build-arg "EMSCRIPTEN_FLAGS=$(EMSCRIPTEN_FLAGS)" \
		--build-arg "EMSCRIPTEN_SDK_TAG=$(EMSCRIPTEN_SDK_TAG)"
else
	docker buildx build libs \
		$(DOCKER_EXTRA_ARGS) \
		--progress plain \
		-f Dockerfile.base \
		-t $(DOCKER_TAG_BASE) \
		--build-arg "CMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)" \
		--build-arg "MESON_BUILD_TYPE=$(MESON_BUILD_TYPE)" \
		--build-arg "EMSCRIPTEN_FLAGS=$(EMSCRIPTEN_FLAGS)" \
		--build-arg "EMSCRIPTEN_SDK_TAG=$(EMSCRIPTEN_SDK_TAG)" \
		--output=type=oci,tar=false,dest="$(DOCKER_OCI_BASE)"
endif
	$(TOUCH) $@

#
#  Using the base image for building the OpenSCAD WASM binary.
#
.image$(VARIANT)-$(ENV).make: .base-image$(VARIANT)-$(ENV).make Dockerfile
ifeq ($(BUILDKIT),0)
	docker build libs/openscad \
		$(DOCKER_EXTRA_ARGS) \
		-f Dockerfile \
		-t $(DOCKER_TAG_OPENSCAD) \
		--build-arg "CMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)" \
		--build-arg "DOCKER_TAG_BASE=$(DOCKER_TAG_BASE)" \
		--build-arg "EMSCRIPTEN_FLAGS=$(EMSCRIPTEN_FLAGS)"
else
	docker buildx build libs/openscad \
		$(DOCKER_EXTRA_ARGS) \
		--progress plain \
		-f Dockerfile \
		-t $(DOCKER_TAG_OPENSCAD) \
		--pull=false \
		--load \
		--build-context $(DOCKER_TAG_BASE)="oci-layout://$(PWD)/$(DOCKER_OCI_BASE)" \
		--build-arg "CMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)" \
		--build-arg "DOCKER_TAG_BASE=$(DOCKER_TAG_BASE)" \
		--build-arg "EMSCRIPTEN_FLAGS=$(EMSCRIPTEN_FLAGS)"
endif
	$(TOUCH) $@

libs: \
	libs/cairo \
	libs/cgal \
	libs/eigen \
	libs/fontconfig \
	libs/freetype \
	libs/libffi \
	libs/glib \
	libs/harfbuzz \
	libs/lib3mf \
	libs/libexpat \
	libs/liblzma \
	libs/libzip \
	libs/openscad \
	libs/boost \
	libs/gmp \
	libs/mpfr \
	libs/zlib \
	libs/libxml2 \
	libs/doubleconversion \
	libs/emscripten-crossfile.meson

SINGLE_BRANCH_MAIN=--branch main --single-branch
SINGLE_BRANCH=--branch master --single-branch
SHALLOW=--depth 1

libs/emscripten-crossfile.meson:
	$(MKDIR_LIBS)
	cp emscripten-crossfile.meson libs/emscripten-crossfile.meson

libs/cairo:
	git -c core.autocrlf=false clone --recurse https://gitlab.freedesktop.org/cairo/cairo.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/libffi:
	git -c core.autocrlf=false clone https://github.com/libffi/libffi.git ${SHALLOW} --branch v3.4.6 --single-branch $@

libs/cgal:
	git -c core.autocrlf=false clone https://github.com/CGAL/cgal.git ${SHALLOW} --branch v6.0.1 --single-branch $@

libs/eigen:
	git -c core.autocrlf=false clone https://gitlab.com/libeigen/eigen.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/fontconfig:
	git -c core.autocrlf=false clone https://gitlab.freedesktop.org/fontconfig/fontconfig ${SHALLOW} ${SINGLE_BRANCH_MAIN} $@
	git -C $@ apply ../../patches/fontconfig.patch

libs/freetype:
	git -c core.autocrlf=false clone https://github.com/freetype/freetype.git ${SHALLOW} ${SINGLE_BRANCH} $@
# git clone https://gitlab.freedesktop.org/freetype/freetype.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/glib:
	test -d $@ || git -c core.autocrlf=false clone https://github.com/kleisauke/glib.git ${SHALLOW} --branch wasm-vips-2.83.2 --single-branch $@

libs/harfbuzz:
	git -c core.autocrlf=false clone https://github.com/harfbuzz/harfbuzz.git ${SHALLOW} ${SINGLE_BRANCH_MAIN} $@

libs/lib3mf:
	git -c core.autocrlf=false clone --recurse https://github.com/3MFConsortium/lib3mf.git ${SHALLOW} --branch v2.3.2 $@
	git -C $@ apply ../../patches/lib3mf.patch

libs/libexpat:
	git -c core.autocrlf=false clone  https://github.com/libexpat/libexpat ${SHALLOW} ${SINGLE_BRANCH} $@

libs/liblzma:
	git -c core.autocrlf=false clone https://github.com/kobolabs/liblzma.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/libzip:
	git -c core.autocrlf=false clone https://github.com/nih-at/libzip.git ${SHALLOW} ${SINGLE_BRANCH_MAIN} $@

libs/zlib:
	git -c core.autocrlf=false clone https://github.com/madler/zlib.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/libxml2:
	git -c core.autocrlf=false clone https://gitlab.gnome.org/GNOME/libxml2.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/doubleconversion:
	git -c core.autocrlf=false clone https://github.com/google/double-conversion ${SHALLOW} --branch v3.3.0 --single-branch $@

libs/openscad:
	git -c core.autocrlf=false clone --recurse https://github.com/openscad/openscad.git ${SHALLOW} ${SINGLE_BRANCH} $@

libs/boost:
	wget https://github.com/boostorg/boost/releases/download/boost-1.87.0/boost-1.87.0-b2-nodocs.tar.xz
ifeq ($(OS),Windows_NT)
	"C:/Program Files/7-Zip/7z.exe" x boost-1.87.0-b2-nodocs.tar.xz
	"C:/Program Files/7-Zip/7z.exe" x boost-1.87.0-b2-nodocs.tar -olibs
	del boost-1.87.0-b2-nodocs.tar.xz boost-1.87.0-b2-nodocs.tar
	move libs\boost-1.87.0 $@
	powershell -Command "(Get-Content libs/boost/tools/build/src/tools/emscripten.jam) -replace '-fwasm-exceptions','-fexceptions' | Set-Content libs/boost/tools/build/src/tools/emscripten.jam"
else
	tar -xJf boost-1.87.0-b2-nodocs.tar.xz -C libs
	rm boost-1.87.0-b2-nodocs.tar.xz
	mv libs/boost-1.87.0 $@
	sed -i 's/-fwasm-exceptions/-fexceptions/' libs/boost/tools/build/src/tools/emscripten.jam
endif

libs/gmp:
	wget https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz
ifeq ($(OS),Windows_NT)
	"C:/Program Files/7-Zip/7z.exe" x gmp-6.3.0.tar.xz
	"C:/Program Files/7-Zip/7z.exe" x gmp-6.3.0.tar -olibs
	del gmp-6.3.0.tar.xz gmp-6.3.0.tar
	move libs\gmp-6.3.0 $@
else
	tar -xJf gmp-6.3.0.tar.xz -C libs
	rm gmp-6.3.0.tar.xz
	mv libs/gmp-6.3.0 $@
endif

libs/mpfr:
	wget https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.xz
ifeq ($(OS),Windows_NT)
	"C:/Program Files/7-Zip/7z.exe" x mpfr-4.2.1.tar.xz
	"C:/Program Files/7-Zip/7z.exe" x mpfr-4.2.1.tar -olibs
	del mpfr-4.2.1.tar.xz mpfr-4.2.1.tar
	move libs\mpfr-4.2.1 $@
else
	tar -xJf mpfr-4.2.1.tar.xz -C libs
	rm mpfr-4.2.1.tar.xz
	mv libs/mpfr-4.2.1 $@
endif

res: \
	res/noto \
	res/liberation \
	res/MCAD

res/liberation:
	git -c core.autocrlf=false clone --recurse https://github.com/shantigilbert/liberation-fonts-ttf.git ${SHALLOW} ${SINGLE_BRANCH} $@

res/noto:
	$(MKDIR_RES_NOTO)
	wget https://github.com/openmaptiles/fonts/raw/master/noto-sans/NotoSans-Regular.ttf -O res/noto/NotoSans-Regular.ttf
	wget https://github.com/openmaptiles/fonts/raw/master/noto-sans/NotoNaskhArabic-Regular.ttf -O res/noto/NotoNaskhArabic-Regular.ttf

res/MCAD:
	git -c core.autocrlf=false clone https://github.com/openscad/MCAD.git ${SHALLOW} ${SINGLE_BRANCH} $@
