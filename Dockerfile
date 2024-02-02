# Build vmaas app with local changes to vmaas-lib
FROM registry.access.redhat.com/ubi8/ubi-minimal

# install postgresql from centos if not building on RHSM system
RUN FULL_RHEL=$(microdnf repolist --enabled | grep rhel-8) ; \
    if [ -z "$FULL_RHEL" ] ; then \
        rpm -Uvh http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/Packages/centos-stream-repos-8-4.el8.noarch.rpm \
                 http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/Packages/centos-gpg-keys-8-4.el8.noarch.rpm && \
        sed -i 's/^\(enabled.*\)/\1\npriority=200/;' /etc/yum.repos.d/CentOS*.repo ; \
    fi

ARG VAR_RPMS=""
RUN microdnf module enable postgresql:12 && \
    microdnf module enable nginx:1.20 && \
    microdnf install --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
        python311 python3.11-pip python3-rpm which nginx rpm-devel git-core shadow-utils diffutils systemd libicu postgresql go-toolset \
        $VAR_RPMS && \
        ln -s /usr/lib64/python3.6/site-packages/rpm /usr/lib64/python3.11/site-packages/rpm && \
    microdnf clean all

RUN git clone https://github.com/RedHatInsights/vmaas.git --branch master /vmaas

WORKDIR /vmaas

ENV LC_ALL=C.utf8
ENV LANG=C.utf8
ARG VAR_POETRY_INSTALL_OPT="--only main"
RUN pip3 install --upgrade pip && \
    pip3 install --upgrade poetry~=1.5
RUN poetry export $VAR_POETRY_INSTALL_OPT -f requirements.txt --output requirements.txt && \
    pip3 install -r requirements.txt

RUN install -m 1777 -d /data && \
    adduser --gid 0 -d /vmaas --no-create-home vmaas
RUN mkdir -p /vmaas/go/src/vmaas && chown -R vmaas:root /vmaas/go
RUN mv /vmaas/vmaas-go/* /vmaas/go/src/vmaas

ENV PYTHONPATH=/vmaas
ENV GOPATH=/vmaas/go \
    PATH=$PATH:/vmaas/go/bin

RUN mkdir /vmaas-lib && chown -R vmaas:root /vmaas-lib

ADD go.* /vmaas-lib/
ADD /vmaas/ /vmaas-lib/vmaas/

WORKDIR /vmaas/go/src/vmaas
RUN go mod edit -replace github.com/redhatinsights/vmaas-lib=/vmaas-lib
RUN go mod tidy
RUN go mod download
RUN go build -v main.go

WORKDIR /vmaas

USER vmaas
