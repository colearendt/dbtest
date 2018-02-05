FROM rocker/r-ver:3.4.3

WORKDIR /wrk
COPY . /wrk

# install packages
RUN apt-get update -y && apt-get install -y \
  curl \
  libcurl4-openssl-dev \
  zlib1g-dev \
  libssl-dev \
  git && \
  R -e 'install.packages("devtools"); devtools::install_deps(".")'

# Add a command that executes tests....
