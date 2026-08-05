#!/bin/bash
# Install R and tidyverse (replaces install-R.sh).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

case "$DISTRO_FAMILY" in
    debian)
        if [[ -z "$DISTRO_CODENAME" ]]; then
            log_error "Cannot determine distro codename; needed for CRAN repo"
            exit 1
        fi

        log_info "Installing R for $DISTRO_ID $DISTRO_CODENAME"

        apt install -y software-properties-common dirmngr wget

        wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
            | tee /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc > /dev/null
        add-apt-repository -y "deb https://cloud.r-project.org/bin/linux/ubuntu ${DISTRO_CODENAME}-cran40/"

        apt update
        apt install -y r-base r-base-dev

        # System libraries needed by tidyverse and friends
        apt install -y \
            libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev \
            libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev \
            libtiff5-dev libjpeg-dev pandoc libwebp-dev

        # Install R packages using Posit Package Manager (precompiled binaries)
        Rscript -e "install.packages(
            c('tidyverse', 'rmarkdown', 'knitr'),
            repos='https://packagemanager.posit.co/cran/__linux__/${DISTRO_CODENAME}/latest',
            Ncpus=parallel::detectCores()
        )"
        ;;
    arch)
        log_info "Installing R for Arch Linux"
        pacman -S --noconfirm --needed r gcc-fortran

        # System libraries for compiling R packages
        pacman -S --noconfirm --needed \
            curl openssl libxml2 fontconfig harfbuzz fribidi \
            freetype2 libpng libtiff libjpeg-turbo pandoc libwebp

        # Install R packages from CRAN source
        Rscript -e "install.packages(
            c('tidyverse', 'rmarkdown', 'knitr'),
            repos='https://cloud.r-project.org',
            Ncpus=parallel::detectCores()
        )"
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "R installation complete"
