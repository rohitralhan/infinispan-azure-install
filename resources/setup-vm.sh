#!/bin/sh

INFINISPAN_VERSION=14.0.7.Final
INFINISPAN_FILENAME=infinispan-server-$INFINISPAN_VERSION

echo "Configuring the VM please wait..."
sudo yum install java-17-openjdk-devel -y -q
printf "export JAVA_HOME=/usr/lib/jvm/jre \nexport PATH=$JAVA_HOME/bin:$PATH" | sudo tee -a /etc/bashrc
source /etc/bashrc
sudo firewall-cmd --zone=public --permanent --add-service=http && sudo firewall-cmd --zone=public --permanent --add-port 11222/tcp && sudo firewall-cmd --zone=public --permanent --add-port 7800/tcp && sudo firewall-cmd --reload && sudo firewall-cmd --list-all
cd ~
echo
echo "####################### Downloading Infinispan #######################"
wget https://downloads.jboss.org/infinispan/$INFINISPAN_VERSION/$INFINISPAN_FILENAME.zip

echo
echo "####################### Setting up Infinispan #######################"

unzip -q $INFINISPAN_FILENAME.zip && mv $INFINISPAN_FILENAME infinispan && ~/infinispan/bin/cli.sh user create developer -p developer -g admin
rm -rf $INFINISPAN_FILENAME.zip
mkdir -p ~/infinispan/server/data/dg
cp ~/infinispan.xml ~/infinispan/server/conf/
sudo chown -R dguser:dguser ~/infinispan/server/data/dg/ && chmod -R 775 ~/infinispan/server/data/dg/

echo 
echo "################################## Configuring/Partitioning the Disk ##################################"

DEVICE=`lsblk -o NAME,SIZE | grep "2T" | awk -F " " 'NR==1{print $1}'`
sudo parted /dev/$DEVICE --script mklabel gpt mkpart xfspart xfs 0% 100%
DEVICE_PARTED=`lsblk -o NAME,SIZE | grep "2T" | awk 'NR==2{print $1}' | awk -F "─" '{print $2}'`

sudo mkfs.xfs /dev/$DEVICE_PARTED -f
sudo partprobe /dev/$DEVICE_PARTED

echo "####################### Mounting the disk #######################"
sudo mount /dev/$DEVICE_PARTED ~/infinispan/server/data/dg

#echo "Starting Infinispan Server"
#nohup ~/infinispan/bin/server.sh -b 0.0.0.0 &

echo "####################### Script executed. Please check console for any errors. #######################"
