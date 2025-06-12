FROM golang:1.24-alpine AS server-builder

ARG GO_DRIVE_COMMIT_ID="HEAD~0"
ARG BUILD_VERSION

ARG GO_DRIVE_BUILD_ROOT="/usr/src/go-drive"

RUN set -eux; \
	mkdir -p /usr/src; \
	apk add --no-cache --virtual build-deps \
		ca-certificates \
		tzdata \
		bash \
		make \
		cmake \
		ninja \
		tar \
		xz \
		build-base \
		git \
		curl \
		wget \
		libc-dev \
		libgcc \
		libstdc++ \
		gcc \
		; \
	mkdir -p /usr/src;

RUN set -eux; \
	git clone https://github.com/devld/go-drive.git ${GO_DRIVE_BUILD_ROOT}; \
	cd ${GO_DRIVE_BUILD_ROOT}; \
	git checkout --force --quiet ${GO_DRIVE_COMMIT_ID}; \
	GO_DRIVE_COMMON_VERSION="${BUILD_VERSION:-$(git rev-parse --short HEAD)}"; \
    GO_DRIVE_COMMON_REV_HASH=$(git rev-parse HEAD); \
    GO_DRIVE_COMMON_BUILD_AT=$(date -R); \
	### build server
	cd ${GO_DRIVE_BUILD_ROOT}; \
	mkdir -p ${GO_DRIVE_BUILD_ROOT}/build; \
	CGO_CFLAGS="-Wno-return-local-addr -D_LARGEFILE64_SOURCE" \
	go build -o build/go-drive -ldflags " \
		-w -s \
		-X 'go-drive/common.Version=${GO_DRIVE_COMMON_VERSION}' \
		-X 'go-drive/common.RevHash=${GO_DRIVE_COMMON_REV_HASH}' \
		-X 'go-drive/common.BuildAt=${GO_DRIVE_COMMON_BUILD_AT}'"; \
	### copy
	mkdir -p /app/data; \
	cd ${GO_DRIVE_BUILD_ROOT}; \
	cp -R ${GO_DRIVE_BUILD_ROOT}/build/go-drive /app/; \
	cp -R ${GO_DRIVE_BUILD_ROOT}/docs/lang /app/lang; \
	cp -R ${GO_DRIVE_BUILD_ROOT}/docs/config.yml /app/;

RUN  \
	# permissions
	find /app -type d -exec chmod 755 {} \; && \
	find /app -type f -exec chmod 644 {} \; && \
	chmod 755 /app/go-drive && \
	ls -al /app/

# 修改配置文件
RUN set -eux; \
	sed 's/data-dir: .\//data-dir: \/app\/data/' -i /app/config.yml; \
	sed 's/web-dir: .\/web/web-dir: \/app\/web/' -i /app/config.yml; \
	sed 's/lang-dir: .\/lang/lang-dir: \/app\/lang/' -i /app/config.yml; \
	sed 's/default-lang: en-US/default-lang: zh-CN/' -i /app/config.yml;

FROM node:24-alpine AS web-builder

ARG GO_DRIVE_COMMIT_ID="HEAD~0"

ARG GO_DRIVE_BUILD_ROOT="/usr/src/go-drive"

RUN set -eux; \
	mkdir -p /usr/src; \
	apk add --no-cache --virtual build-deps \
		ca-certificates \
		tzdata \
		bash \
		make \
		cmake \
		ninja \
		tar \
		xz \
		build-base \
		git \
		curl \
		wget \
		; \
	mkdir -p /usr/src;

RUN set -eux; \
	git clone https://github.com/devld/go-drive.git ${GO_DRIVE_BUILD_ROOT}; \
	cd ${GO_DRIVE_BUILD_ROOT}; \
	git checkout --force --quiet ${GO_DRIVE_COMMIT_ID}; \
	### build web
	cd ${GO_DRIVE_BUILD_ROOT}/web; \
	npm install; \
	npm run build; \
	### copy
	mkdir -p /app/; \
	cd ${GO_DRIVE_BUILD_ROOT}; \
	cp -R ${GO_DRIVE_BUILD_ROOT}/web/dist /app/web;

RUN  \
	# permissions
	find /app -type d -exec chmod 755 {} \; && \
	find /app -type f -exec chmod 644 {} \; && \
	ls -al /app/

FROM alpine:latest

# 配置环境变量和工作目录
WORKDIR /app

RUN set -eux; \
	apk add --no-cache \
		tzdata \
		ca-certificates \
		; \
	rm -rf /tmp/* /var/cache/apk/*;

COPY --from=server-builder /app /app
COPY --from=web-builder /app/web /app/web

LABEL \
	description="go-drive" \
    maintainer="Custom Auto Build"

# 定义容器暴露的端口
EXPOSE 8089

# 挂载数据目录
VOLUME /app/data

STOPSIGNAL SIGTERM

# 设置容器启动命令
ENTRYPOINT ["/app/go-drive"]

# 设置容器启动命令(ENTRYPOIN[]的默认参数)
CMD ["-c", "/app/config.yml"]
