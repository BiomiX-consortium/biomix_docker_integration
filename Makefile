run:
	nextflow run ./nf_workflow.nf -resume -c nextflow.config \
		--biomix_root ./bin/BiomiX2.5 \
		--command_dir ./test/fixtures/egas_transcriptomics_mutated_vs_unmutated \
		--transcriptomics_matrix ./bin/BiomiX2.5/Example_dataset/EGAS00001001746/RNA_seq/EGAS00001001746_transcriptomics.tsv \
		--metadata ./bin/BiomiX2.5/Example_dataset/EGAS00001001746/Metadata/EGAS00001001746_metadata_CLL.tsv \
		--group_1 mutated \
		--group_2 unmutated

run_importer_workflow:
	nextflow run ./nf_workflow_importer.nf -resume -c nextflow.config

run_slurm:
	nextflow run ./nf_workflow.nf -resume -c nextflow_slurm.config \
		--biomix_root ./bin/NextflowModules/bin/BiomiX2.5 \
		--command_dir ./test/fixtures/egas_transcriptomics_mutated_vs_unmutated \
		--transcriptomics_matrix ./bin/BiomiX2.5/Example_dataset/EGAS00001001746/RNA_seq/EGAS00001001746_transcriptomics.tsv \
		--metadata ./bin/BiomiX2.5/Example_dataset/EGAS00001001746/Metadata/EGAS00001001746_metadata_CLL.tsv \
		--group_1 mutated \
		--group_2 unmutated

run_docker:
	nextflow run ./nf_workflow.nf -resume -with-docker <CONTAINER NAME>

init_modules:
	git submodule update --init --recursive

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

# Local single-arch builds — uses native arch by default, override with LOCAL_PLATFORM=linux/amd64.
IMG_biomix_base:
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_base.Dockerfile -t biomix-base .

IMG_biomix_transcriptomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_transcriptomics.Dockerfile -t biomix-transcriptomics .

IMG_biomix_methylomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_methylomics.Dockerfile -t biomix-methylomics .

IMG_biomix_mofa: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_mofa.Dockerfile -t biomix-mofa .

IMG_biomix_metabolomics: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_metabolomics.Dockerfile -t biomix-metabolomics .

IMG_biomix_gui: IMG_biomix_base
	docker buildx build --platform $(LOCAL_PLATFORM) --load \
		-f docker/biomix_gui.Dockerfile -t biomix-gui .

# Multi-arch build and push to GHCR.
# Child images pull biomix-base from GHCR so both architectures resolve correctly.
push_biomix_base: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_base.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-base:latest \
		--push .

push_biomix_transcriptomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_transcriptomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-transcriptomics:latest \
		--push .

push_biomix_methylomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_methylomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-methylomics:latest \
		--push .

push_biomix_mofa: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_mofa.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-mofa:latest \
		--push .

push_biomix_metabolomics: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_metabolomics.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-metabolomics:latest \
		--push .

push_biomix_gui: setup_buildx
	docker buildx build \
		--platform $(PLATFORMS) \
		-f docker/biomix_gui.Dockerfile \
		-t $(GHCR_NAMESPACE)/biomix-gui:latest \
		--push .

push_all: push_biomix_base push_biomix_transcriptomics push_biomix_methylomics push_biomix_mofa push_biomix_metabolomics push_biomix_gui