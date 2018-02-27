FROM rocker/r-ver:3.4.3

WORKDIR /wrk
COPY . /wrk

# install packages
RUN apt-get update -y && apt-get install -y \
  curl \
  libcurl4-openssl-dev \
  zlib1g-dev \
  libssl-dev \
  sqlite3 \
  git \
  && \
  R -e 'install.packages("devtools"); devtools::install_deps(".")'

# install the repo under test
ENV DBPLYR_REF=master
RUN R -e 'devtools::install_github("tidyverse/dbplyr",Sys.getenv("DBPLYR_REF"))'

# Add a command that executes tests....



