GHCR_NAMESPACE = ghcr.io/biomix-consortium
PLATFORMS      = linux/amd64,linux/arm64
BUILDER        = multiarch-builder

# Image tag — defaults to "latest"; override with e.g. `make TAG=V2 IMG_all`
TAG ?= latest

# Auto-detect native arch for local builds (override: make LOCAL_PLATFORM=linux/amd64 IMG_*)
_ARCH := $(shell uname -m)
ifneq (,$(filter $(_ARCH),arm64 aarch64))
LOCAL_PLATFORM ?= linux/arm64
else
LOCAL_PLATFORM ?= linux/amd64
endif

# Arch suffix used to tag native single-arch pushes (linux/arm64 -> arm64).
ARCH_SUFFIX = $(subst linux/,,$(LOCAL_PLATFORM))

# Every image except the base. Rules below match these via the % stem in
# each family's pattern rule; biomix_base gets its own explicit rule per
# family since it doesn't take --build-arg BASE_TAG and (for IMG_*) is a
# prerequisite of the others rather than a dependent of itself.
IMAGES := gui transcriptomics metabolomics methylomics mofa_diablo snf_nemo interpretation pramigo

# Dockerfiles/targets use underscores (mofa_diablo); GHCR tags use dashes
# (biomix-mofa-diablo). $(call tag_name,mofa_diablo) -> biomix-mofa-diablo.
tag_name = biomix-$(subst _,-,$(1))

# Ensure a multi-platform buildx builder exists and is active.
setup_buildx:
	docker buildx create --name $(BUILDER) --driver docker-container --bootstrap --use 2>/dev/null || \
	docker buildx use $(BUILDER)

# ---------------------------------------------------------------------------
# Local single-arch builds — uses native arch by default.
# Tagged with the FULL image name (ghcr.io/biomix-consortium/...:$(TAG)) so that
# generateRunnerFunction() in BiomiX_BETA.r finds them in the local cache
# without ever needing to reach out to the registry.
# ---------------------------------------------------------------------------

IMG_biomix_base:
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_base.Dockerfile -t $(GHCR_NAMESPACE)/biomix-base:$(TAG) .

IMG_biomix_%: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		--build-arg BASE_TAG=$(TAG) \
		-f docker/biomix_$*.Dockerfile -t $(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG) .

IMG_all: IMG_biomix_base $(addprefix IMG_biomix_,$(IMAGES))

# ---------------------------------------------------------------------------
# Multi-arch build and push to GHCR (organization biomix-consortium).
# Builds both linux/amd64 and linux/arm64 in one buildx invocation via QEMU
# emulation. Tag defaults to "latest"; override with `make TAG=V2 push_all`
# to avoid overwriting :latest. Prefer push_arch_*/manifest_* (below) in CI,
# which build each arch natively instead of emulating.
# ---------------------------------------------------------------------------

push_biomix_base: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_base.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-base:$(TAG) \
		--push .

push_biomix_%: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg BASE_TAG=$(TAG) \
		-f docker/biomix_$*.Dockerfile \
		-t $(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG) \
		--push .

push_all: push_biomix_base $(addprefix push_biomix_,$(IMAGES))

# ---------------------------------------------------------------------------
# Native single-arch build and push, tagged with an arch suffix (e.g. :latest-amd64).
# Unlike push_* above, these build only $(LOCAL_PLATFORM) — no QEMU emulation.
# Used by CI, which runs these natively on real amd64 and arm64 runners, then
# combines the two arch-tagged images into one multi-arch manifest with the
# manifest_* targets below. Override LOCAL_PLATFORM to cross-build manually.
# ---------------------------------------------------------------------------

push_arch_biomix_base: setup_buildx
	docker buildx build --platform $(LOCAL_PLATFORM) \
		-f docker/biomix_base.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-base:$(TAG)-$(ARCH_SUFFIX) \
		--push .

push_arch_biomix_%: setup_buildx
	docker buildx build --platform $(LOCAL_PLATFORM) \
		--build-arg BASE_TAG=$(TAG) \
		-f docker/biomix_$*.Dockerfile \
		-t $(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG)-$(ARCH_SUFFIX) \
		--push .

push_arch_all: push_arch_biomix_base $(addprefix push_arch_biomix_,$(IMAGES))

# ---------------------------------------------------------------------------
# Merge the :$(TAG)-amd64 and :$(TAG)-arm64 images pushed above into a single
# multi-arch manifest at :$(TAG). Run after both arches have been pushed.
# ---------------------------------------------------------------------------

manifest_biomix_%:
	docker buildx imagetools create -t $(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG) \
		$(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG)-amd64 \
		$(GHCR_NAMESPACE)/$(call tag_name,$*):$(TAG)-arm64

manifest_all: $(addprefix manifest_biomix_,base $(IMAGES))
