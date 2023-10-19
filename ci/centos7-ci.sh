#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

. ./ci/common.sh

install_dependencies() {
    export_or_prefix

    # install build & runtime deps
    yum install -y wget tar gcc automake autoconf libtool make unzip \
        git sudo openldap-devel which ca-certificates openssl-devel \
        epel-release >/dev/null

    # install newer curl
    yum makecache > /dev/null
    yum install -y libnghttp2-devel > /dev/null
    install_curl > /dev/null

    # install openresty to make apisix's rpm test work
    yum install -y yum-utils && yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo > /dev/null 2>&1
    yum install -y openresty-1.21.4.2 openresty-debug-1.21.4.2 openresty-openssl111-debug-devel pcre pcre-devel > /dev/null

    # install luarocks
    ./utils/linux-install-luarocks.sh

    # install etcdctl
    ./ci/linux-install-etcd-client.sh

    # install vault cli capabilities
    install_vault_cli

    # install test::nginx
    yum install -y cpanminus perl > /dev/null
    cpanm --notest Test::Nginx IPC::Run > build.log 2>&1 || (cat build.log && exit 1)

    # add go1.15 binary to the path
    mkdir build-cache
    # centos-7 ci runs on a docker container with the centos image on top of ubuntu host. Go is required inside the container.
    cd build-cache/ && wget -q https://golang.org/dl/go1.17.linux-amd64.tar.gz && tar -xf go1.17.linux-amd64.tar.gz
    export PATH=$PATH:$(pwd)/go/bin
    cd ..
    
    sysctl -a | grep net.ipv4.ip_local_port_range
    sysctl -a | grep net.ipv4.ip_local_reserved_ports
    
    # install and start grpc_server_example
    cd t/grpc_server_example

    CGO_ENABLED=0 go build
    ./grpc_server_example \
        -grpc-address :50051 -grpcs-address :50052 -grpcs-mtls-address :50053 -grpc-http-address :50054 \
        -crt ../certs/apisix.crt -key ../certs/apisix.key -ca ../certs/mtls_ca.crt \
        > grpc_server_example.log 2>&1 &

	if [ $? != 0 ];then
		cat grpc_server_example.log
		sleep 1
	    ss -antp | grep 5005
	    sleep 2
	    ss -antp | grep 5005
	    exit 1
	fi
	
    cd ../../
    # wait for grpc_server_example to fully start
	
	sleep 3
	ss -antp | grep 5005
	GRPC_PROC=`ps -ef | grep grpc | grep -v grep`
	#echo $GRPC_PROC
	if [[ $GRPC_PROC == "" ]];then 
		cat grpc_server_example.log
		exit 1
	fi
	exit 0

    # installing grpcurl
    install_grpcurl

    # install nodejs
    install_nodejs

    # grpc-web server && client
    cd t/plugin/grpc-web
    ./setup.sh
    # back to home directory
    cd ../../../

    # install dependencies
    git clone https://github.com/openresty/test-nginx.git test-nginx
    create_lua_deps
}

run_case() {
    export_or_prefix
    make init
    set_coredns
    # run test cases
    FLUSH_ETCD=1 prove --timer -Itest-nginx/lib -I./ -r ${TEST_FILE_SUB_DIR} | tee /tmp/test.result
    rerun_flaky_tests /tmp/test.result
}

case_opt=$1
case $case_opt in
    (install_dependencies)
        install_dependencies
        ;;
    (run_case)
        run_case
        ;;
esac
