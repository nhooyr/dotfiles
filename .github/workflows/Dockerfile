FROM ubuntu

RUN apt-get update
RUN apt-get install -y npm
RUN apt-get install -y curl
RUN apt-get install -y git
RUN apt-get install -y fish
RUN apt-get install -y locales

RUN locale-gen en_US.UTF-8

ENV LC_ALL=en_US.UTF-8
ENV PAGER=cat
ENV CI=true
ENV MAKEFLAGS="--jobs=8 --output-sync=target"

RUN npm install -g prettier
RUN curl -L https://github.com/mvdan/sh/releases/download/v2.6.4/shfmt_v2.6.4_linux_amd64 > /usr/local/bin/shfmt \
  && chmod +x /usr/local/bin/shfmt
