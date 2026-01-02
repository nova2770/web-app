###############
### STAGE 1: Build app
###############
ARG BUILDER_IMAGE=node:22.9.0-alpine
ARG NGINX_IMAGE=nginx:1.27.4-alpine3.21-slim

FROM $BUILDER_IMAGE AS builder
ARG NPM_REGISTRY_URL=https://registry.npmjs.org/
ARG BUILD_ENVIRONMENT_OPTIONS="--configuration production --output-hashing=none --base-href=/"

# 版本信息参数
ARG BUILD_VERSION=unknown
ARG BUILD_COMMIT=unknown
ARG BUILD_DATE=unknown

# Set the environment variable to increase Node.js memory limit
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN apk add --no-cache git

WORKDIR /usr/src/app

ENV PATH=/usr/src/app/node_modules/.bin:$PATH

COPY package*.json ./

RUN npm cache clear --force
RUN npm config set fetch-retry-maxtimeout 120000
RUN npm config set registry $NPM_REGISTRY_URL --location=global

# 使用 npm install 安装所有依赖（包括 devDependencies）
RUN npm install

# 复制源代码
COPY . .

# 构建应用
RUN sh -c "ng build $BUILD_ENVIRONMENT_OPTIONS"

# 创建版本信息文件
RUN echo "Version: ${BUILD_VERSION}" > /usr/src/app/dist/web-app/browser/VERSION.txt && \
    echo "Commit: ${BUILD_COMMIT}" >> /usr/src/app/dist/web-app/browser/VERSION.txt && \
    echo "Build Date: ${BUILD_DATE}" >> /usr/src/app/dist/web-app/browser/VERSION.txt

###############
### STAGE 2: Serve app with nginx ###
###############
FROM $NGINX_IMAGE

# 复制构建产物
COPY --from=builder /usr/src/app/dist/web-app/browser /usr/share/nginx/html

# 复制自定义 Nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 安装 envsubst（用于运行时环境变量替换）
RUN apk add --no-cache gettext

EXPOSE 80

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

# 启动时替换环境变量并启动 Nginx
# 如果存在 env.template.js，则进行环境变量替换
CMD ["/bin/sh", "-c", "if [ -f /usr/share/nginx/html/assets/env.template.js ]; then envsubst < /usr/share/nginx/html/assets/env.template.js > /usr/share/nginx/html/assets/env.js; fi && exec nginx -g 'daemon off;'"]
