#
# Base image for Nginx
#

FROM dockermediacloud/base:latest

# Install packages
RUN \
    #
    # Install newest Nginx
    curl -L https://nginx.org/keys/nginx_signing.key | apt-key add - && \
    echo "deb https://nginx.org/packages/mainline/ubuntu/ xenial nginx" > /etc/apt/sources.list.d/nginx.list && \
    echo "deb-src https://nginx.org/packages/mainline/ubuntu/ xenial nginx" > /etc/apt/sources.list.d/nginx.list && \
    apt-get -y update && \
    apt-get -y --no-install-recommends install nginx && \
    true

# Replace configuration with our own
RUN rm -rf /etc/nginx/
COPY nginx/ /etc/nginx/
