
# file=image-syncer-v1.3.1-linux-amd64.tar.gz
# https://ghproxy.com/https://github.com/AliyunContainerService/image-syncer/releases/download/v1.3.1/$file

# https://gitee.com/infrastlabs/fk-image-syncer/releases/download/v23.4.25/image-syncer-x64.tar.gz
# https://gitee.com/infrastlabs/fk-image-syncer/releases/download/v23.4.25/image-syncer-arm64.tar.gz
test -z "$(uname -a |grep aarch64)" && arch=x64 || arch=arm64;
file=image-syncer-$arch.tar.gz
test -s "$file" || curl -O -fSL https://gitee.com/infrastlabs/fk-image-syncer/releases/download/v23.4.25/$file
# test -s ./image-syncer || tar -zxf $file #解压后README.md会替换(更新README2.md)
tar -zxf $file; rm -f image-syncer; mv image-syncer-$arch image-syncer

function errExit(){
   echo "ERR: $1"
   exit 1
}
function startSync(){
source /etc/profile
# DOCKER_REGISTRY_DST2_DOMAIN=deploy.xxx.com.ssl
match=$(cat /etc/hosts |grep $DOCKER_REGISTRY_DST2_DOMAIN)

# hosts
# test -z "$match" && echo "$DOCKER_REGISTRY_DST2_IP $DOCKER_REGISTRY_DST2_DOMAIN" >> /etc/hosts
if [ -z "$match" ]; then
   cat <<EOF |sudo tee -a /etc/hosts
$DOCKER_REGISTRY_DST2_IP $DOCKER_REGISTRY_DST2_DOMAIN
EOF
fi
cat /etc/hosts |grep "$DOCKER_REGISTRY_DST2_DOMAIN"

# $authyml
authyml=/tmp/auth.yml; cat auth.yml > $authyml
# registry.deploy.xxx.com.ssl:18443: #DST2_DOMAIN
sed -i "s/.*#DST2_DOMAIN/${DOCKER_REGISTRY_DST2_DOMAIN}:18443: #DST2_DOMAIN/g" $authyml
sed -i "s/username: .*#dpRegistry/username: ${DOCKER_REGISTRY_USER_dpinner} #dpRegistry/g" $authyml
sed -i "s/password: .*#dpRegistry/password: ${DOCKER_REGISTRY_PW_dpinner} #dpRegistry/g" $authyml
# 
edgeRegistry_USER=admin; edgeRegistry_PW=admin123
sed -i "s/username: .*#edgeRegistry/username: ${edgeRegistry_USER} #edgeRegistry/g" $authyml
sed -i "s/password: .*#edgeRegistry/password: ${edgeRegistry_PW} #edgeRegistry/g" $authyml
cat $authyml |grep -v password

# certs: 
   # ref1: syncer's Dockerfile
   # mkdir -p /etc/ssl/certs && update-ca-certificates --fresh

   # ref2: .psu/dpregistry.sh
   # headless @ armbian in /opt |14:11:18  
   # $ sudo bash set-certs.sh 
   # $ find /etc/docker/certs.d/
   # /etc/docker/certs.d/deploy.xxx.com.ssl:18443/deploy.xxx.com.ssl.crt

# --proc 1 #多了hub取不到
# DO: 按type,splitBatch
./image-syncer $proc --auth $authyml --images ./images.yml --arch=amd64 #x64Only
./image-syncer $proc --auth $authyml --images ./images.multi.yml --arch=amd64 --arch=arm64 #--arch amd64,arm64
}

function genImgList(){
:> images.yml; :> images.multi.yml
cat $1 |grep -Ev "^#|^$" |awk '{print $1}' |while read one; do
   src=$(echo $one |cut -d'|' -f1); multi=$(echo $one |cut -d'|' -f2); 
   test "$src" == "$multi" && multi=""; echo "one: $src|$multi"
   test -z "$multi" && imgYml=images.yml || imgYml=images.multi.yml
   
   plain=$(echo $src |sed "s^.*.aliyuncs.com/^^g"|sed "s^ghcr.io/^^g" |sed "s^/^-^g")
   dst="registry.cn-shenzhen.aliyuncs.com/infrasync/$plain"
   if [ "true" != "$tlsPrivate" ]; then
      #0A: 从hub转存infrasync
      proc="--proc 1" #多了hub取不到
      # src: dst
      
      #非ali仓,才转存
      match0=$(echo $src |grep "aliyuncs.com") #registry.cn-shenzhen.aliyuncs.com
      if [ -z "$match0" ]; then
         echo "$src: $dst" >> $imgYml
      fi
   else #ERR: unsupported manifest type: application/vnd.oci.image.index.v1+json
      # 0B: 从ali仓转存priRegistry: repo/ns/img:ver >> infrasync/ns-img:ver
      proc="--proc 5"
      # dst:dst2
      # dst2="$DOCKER_REGISTRY_DST2_IP:18443/infrasync/$plain"
      dst2="$DOCKER_REGISTRY_DST2_DOMAIN:18443/infrasync/$plain"
      
      # ali仓: dst=$src
      match1=$(echo $src |grep -E "aliyuncs.com")
      test -z "$match1" || dst=$src #ali: 使用原仓
      echo "$dst: $dst2" >> $imgYml
   fi
done
cat images.yml; cat images.multi.yml
}

# syncer ok @headless-Dind
sudo bash ../../../kedge/regcert.sh
sleep 3

# test "" == "$1" && errExit "please with src.txt"
test "" == "$1" && tlsPrivate=false || tlsPrivate=true
# tlsPrivate=false
src=src.txt
# test "true" == "$tlsPrivate" && src=src.txt || src=src0_dbg.txt
DOCKER_REGISTRY_DST2_IP=172.25.23.194 #172.17.0.196 #172.25.23.194
DOCKER_REGISTRY_DST2_DOMAIN="server.k8s.local"
genImgList $src #$1
startSync

# TODO before sync:
# bash ../../kedge/regcert.sh
