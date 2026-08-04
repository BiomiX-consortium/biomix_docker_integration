GHCR_NAMESPACE = ghcr.io/biomix-consortium
PLATFORMS      = linux/amd64,linux/arm64
BUILDER        = multiarch-builder

# Auto-detect native arch for local builds (override: make LOCAL_PLATFORM=linux/amd64 IMG_*)
_ARCH := $(shell uname -m)
ifeq ($(_ARCH),arm64)
LOCAL_PLATFORM ?= linux/arm64
else
LOCAL_PLATFORM ?= linux/amd64
endif

# Ensure a multi-platform buildx builder exists and is active.
setup_buildx:
	docker buildx create --name $(BUILDER) --driver docker-container --bootstrap --use 2>/dev/null || \
	docker buildx use $(BUILDER)

# ---------------------------------------------------------------------------
# Local single-arch builds — uses native arch by default.
# Tagged with the FULL image name (ghcr.io/biomix-consortium/...:V2) so that
# generateRunnerFunction() in BiomiX_BETA.r finds them in the local cache
# without ever needing to reach out to the registry.
# ---------------------------------------------------------------------------

IMG_biomix_base:
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_base.Dockerfile -t $(GHCR_NAMESPACE)/biomix-base:V2 .

IMG_biomix_gui: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_gui.Dockerfile -t $(GHCR_NAMESPACE)/biomix-gui:V2 .

IMG_biomix_transcriptomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_transcriptomics.Dockerfile -t $(GHCR_NAMESPACE)/biomix-transcriptomics:V2 .

IMG_biomix_metabolomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_metabolomics.Dockerfile -t $(GHCR_NAMESPACE)/biomix-metabolomics:V2 .

IMG_biomix_methylomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_methylomics.Dockerfile -t $(GHCR_NAMESPACE)/biomix-methylomics:V2 .

IMG_biomix_mofa_diablo: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_mofa_diablo.Dockerfile -t $(GHCR_NAMESPACE)/biomix-mofa-diablo:V2 .

IMG_biomix_snf_nemo: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_snf_nemo.Dockerfile -t $(GHCR_NAMESPACE)/biomix-snf-nemo:V2 .

IMG_biomix_interpretation: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_interpretation.Dockerfile -t $(GHCR_NAMESPACE)/biomix-interpretation:V2 .

IMG_all: IMG_biomix_base IMG_biomix_gui IMG_biomix_transcriptomics IMG_biomix_metabolomics IMG_biomix_methylomics IMG_biomix_mofa_diablo IMG_biomix_snf_nemo IMG_biomix_interpretation

# ---------------------------------------------------------------------------
# Multi-arch build and push to GHCR (organizzazione biomix-consortium,
# tag V2 per non sovrapporsi alle immagini :latest del collega).
# ---------------------------------------------------------------------------

push_biomix_base: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_base.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-base:V2 \
		--push .

push_biomix_gui: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_gui.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-gui:V2 \
		--push .

push_biomix_transcriptomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_transcriptomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-transcriptomics:V2 \
		--push .

push_biomix_metabolomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_metabolomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-metabolomics:V2 \
		--push .

push_biomix_methylomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_methylomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-methylomics:V2 \
		--push .

push_biomix_mofa_diablo: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_mofa_diablo.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-mofa-diablo:V2 \
		--push .

push_biomix_snf_nemo: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_snf_nemo.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-snf-nemo:V2 \
		--push .

push_biomix_interpretation: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_interpretation.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-interpretation:V2 \
		--push .

push_all: push_biomix_base push_biomix_gui push_biomix_transcriptomics push_biomix_metabolomics push_biomix_methylomics push_biomix_mofa_diablo push_biomix_snf_nemo push_biomix_interpretation