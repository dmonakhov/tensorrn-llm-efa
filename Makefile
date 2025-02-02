IMAGE_BASE_NAME ?= cuda
IMAGE_NAME ?= tensorrt-llm
IMAGE_BASE_REPO=nvidia/
IMAGE_BASE_TAG  ?= 12.4.0-devel-ubuntu22.04
AWS_OFI_NCCL_VER ?= 1.12.0-aws
AWS_EFA_INSTALLER_VER ?=1.34.0

# podman:// or dockerd://
CT_RUNTIME ?= dockerd://
EXPORT_PATH ?= ..
ZSTD_COMPRESS_OPTIONS ?= --ultra -12

TAG=${IMAGE_BASE_TAG}-efa-${AWS_OFI_NCCL_VER}
TAG_LLAMA=${IMAGE_BASE_TAG}-llama
TAG_PHI=${IMAGE_BASE_TAG}-phi

MPI_HOSTFILE ?= ~/.ssh/mpi_hosts.txt


fetch:
	docker pull "${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}"
build:
	docker build --network=host --progress plain --rm \
		--tag "${IMAGE_NAME}:${TAG}" \
		--build-arg IMAGE_BASE="${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}" \
		--build-arg AWS_OFI_NCCL_VER="${AWS_OFI_NCCL_VER}" \
		--build-arg AWS_EFA_INSTALLER_VER=${AWS_EFA_INSTALLER_VER} .

build-vanilla: build-llama build-phi

build-llama:
	docker build --network=host --progress plain --rm \
		--tag "${IMAGE_NAME}:${TAG_LLAMA}" \
		--build-arg IMAGE_BASE="${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}" \
		--build-arg MODEL_TYPE="llama" \
		-f Dockerfile.vanilla .
build-phi:
	docker build --network=host --progress plain --rm \
		--tag "${IMAGE_NAME}:${TAG_PHI}" \
		--build-arg IMAGE_BASE="${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}" \
		--build-arg MODEL_TYPE="phi" \
		-f Dockerfile.vanilla .

tar-img:
	docker save \
		"${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}" \
		"${IMAGE_NAME}:${TAG}"  | \
		zstdmt ${ZSTD_COMPRESS_OPTIONS} -v -f -o ${EXPORT_PATH}/${IMAGE_NAME}-${TAG}.tar.zst

tar-img-vanilla:
	docker save \
		"${IMAGE_BASE_REPO}${IMAGE_BASE_NAME}:${IMAGE_BASE_TAG}" \
		"${IMAGE_NAME}:${TAG_LLAMA}" \
		"${IMAGE_NAME}:${TAG_PHI}"| \
		zstdmt ${ZSTD_COMPRESS_OPTIONS} -v -f -o ${EXPORT_PATH}/${IMAGE_NAME}-${TAG_LLAMA}.tar.zst
#		| \



mpi-deploy-img:
	# MPICAT see https://github.com/dmonakhov/gpu_toolbox/blob/main/mpitools/README.md#cat1-for-mpi-environment	
	cat ${EXPORT_PATH}/${IMAGE_NAME}-${TAG}.tar.zst | \
	mpirun -N 1 -hostfile ${MPI_HOSTFILE} bash -c 'mpicat | zstdcat | docker load'

enroot-img:
	if [ -e ${EXPORT_PATH}/${IMAGE_NAME}+${TAG}.sqsh ]; then unlink ${EXPORT_PATH}/${IMAGE_NAME}+${TAG}.sqsh; fi
	enroot import -o ${EXPORT_PATH}/${IMAGE_NAME}+${TAG}.sqsh ${CT_RUNTIME}${IMAGE_NAME}:${TAG}
