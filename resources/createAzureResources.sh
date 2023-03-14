
# Variable block
let "randomIdentifier=$RANDOM*$RANDOM"
location="East US"
resourceGroup="openenv-z8vkz"
resPrefix="dg"

########### VNet Params #########################
vNet="$resPrefix-vNet-vms"
addressPrefixVNet="10.0.0.0/16"
subnetFrontEnd="$resPrefix-frontend-subnet-vms"
subnetPrefixFrontEnd="10.0.2.0/24"
nsgFrontEnd="$resPrefix-nsg-frontend-vm0"
publicIpWeb="$resPrefix-public-ip-web-vm0"
nicWeb="$resPrefix-nic-web-vm0"
image="RedHat:RHEL:91-gen2:latest"
login="dguser"
pwd="GRIDP@ssw0rd"
vmWeb="$resPrefix-vm-web0"
sku="STANDARD"
vmSize="Standard_E8-4s_v5"
numVM=3

########### Data Disk #########################
dataDiskName="$resPrefix-$vmname-DataDisk"
diskAccess="ReadWrite"
diskSize=2048
###############################################

###############################################
# LB VNet Param
lbpipVNetName="$resPrefix-lbpipVnet"
lbpipAddrPrefixVNet="10.1.0.0/16"
lbpipSubnetBackEndName="$resPrefix-ben01"
lbpipSubnetPrefixFrontEnd="10.1.0.0/24"
# LB Public Params
lbpipName="$resPrefix-lbPIP"
lbZone="1"

lbName="$resPrefix-lb"
lbBackendPoolName="$resPrefix-bkp"
lbFrontEndIpName="$resPrefix-fip"
lbProbeName="$resPrefix-lbprobe"
lbRuleName="$resPrefix-lbrule"
###############################################


# Create a resource group
##echo "Creating $resourceGroup in $location..."
##az group create --name $resourceGroup --location "$location" --tags $tag

# Create a Load Balancer with a public IP and create an LB rule
#az network vnet create --name $lbpipVNetName --location "$location" --resource-group $resourceGroup --address-prefix $lbpipAddrPrefixVNet --subnet-name $lbpipSubnetBackEndName --subnet-prefix $lbpipSubnetPrefixFrontEnd -o none

echo "Creating Public IP for Load Balancer"
az network public-ip create --name $lbpipName --resource-group $resourceGroup --sku $sku --zone $lbZone -o none

echo "Creating Load Balancer"
az network lb create --resource-group $resourceGroup --name $lbName --sku Standard --public-ip-address $lbpipName --frontend-ip-name $lbFrontEndIpName --backend-pool-name $lbBackendPoolName -o none

echo "Creating Load Balancer Probe"
az network lb probe create --resource-group $resourceGroup --lb-name $lbName --name $lbProbeName --protocol Tcp --port 11222 -o none

echo "Creating Load Balancer Rule"
az network lb rule create --resource-group $resourceGroup --lb-name $lbName --name $lbRuleName --protocol Tcp --frontend-port 11222 --backend-port 11222 --frontend-ip-name $lbFrontEndIpName --backend-pool-name $lbBackendPoolName --probe-name $lbProbeName -o none

# Create a virtual network and a front-end subnet.
echo "Creating $vNet and $subnetFrontEnd"
az network vnet create --resource-group $resourceGroup --name $vNet --address-prefix $addressPrefixVNet  --location "$location" --subnet-name $subnetFrontEnd --subnet-prefix $subnetPrefixFrontEnd -o none


for i in `seq 1 $numVM`
do
        ### Create a network security group (NSG) for the front-end subnet.
        echo "Creating $nsgFrontEnd$i for $subnetFrontEnd"
        az network nsg create --resource-group $resourceGroup --name $nsgFrontEnd$i --location "$location" -o none

        ### Create NSG rules to allow HTTP & HTTPS traffic inbound.
        echo "Creating $nsgFrontEnd rules in $nsgFrontEnd to allow port 11222 and 7800 inbound traffic"
        az network nsg rule create --resource-group $resourceGroup --nsg-name $nsgFrontEnd$i --name Allow-11222-All --access Allow --protocol Tcp --direction Inbound --priority 100 --source-address-prefix Internet --source-port-range "*" --destination-address-prefix "*" --destination-port-range 11222 -o none
        az network nsg rule create --resource-group $resourceGroup --nsg-name $nsgFrontEnd$i --name Allow-07800-All --access Allow --protocol Tcp --direction Inbound --priority 200 --source-address-prefix Internet --source-port-range "*" --destination-address-prefix "*" --destination-port-range 7800 -o none

        ### Create an NSG rule to allow SSH traffic in from the Internet to the front-end subnet.
        echo "Creating NSG rule in $nsgFrontEnd$i to allow inbound SSH traffic"
        az network nsg rule create --resource-group $resourceGroup --nsg-name $nsgFrontEnd$i --name Allow-SSH-All --access Allow --protocol Tcp --direction Inbound --priority 300 --source-address-prefix Internet --source-port-range "*" --destination-address-prefix "*" --destination-port-range 22  -o none

        ### Associate the front-end NSG to the front-end subnet.
        echo "Associate $nsgFrontEnd$i to $subnetFrontEnd"
        az network vnet subnet update --vnet-name $vNet --name $subnetFrontEnd --resource-group $resourceGroup --network-security-group $nsgFrontEnd$i -o none

        # Create a public IP address for the web server VM.
        echo "Creating $publicIpWeb$i for $vmWeb$i"
        az network public-ip create --resource-group $resourceGroup --name $publicIpWeb$i --sku $sku  --zone $lbZone -o none
        PUBLIC_IP=$(az network public-ip show --resource-group $resourceGroup --name $publicIpWeb$i --query ipAddress -o tsv)

        # Create a NIC for the web server VM.
        echo "Creating $nicWeb for $vmWeb$i"
        az network nic create --resource-group $resourceGroup --name $nicWeb$i --vnet-name $vNet --subnet $subnetFrontEnd --network-security-group $nsgFrontEnd$i \
           --public-ip-address $publicIpWeb$i --lb-name $lbName --lb-address-pools $lbBackendPoolName -o none
        
        # Create a Web Server VM in the front-end subnet.
        echo "Creating $vmWeb$i in $subnetFrontEnd"
        az vm create --resource-group $resourceGroup --name $vmWeb$i --nics $nicWeb$i --image $image  --size $vmSize --admin-username $login --admin-password $pwd --public-ip-sku $sku --data-disk-sizes-gb $diskSize --data-disk-caching $diskAccess --os-disk-delete-option delete --data-disk-delete-option delete --nic-delete-option delete -o none
        
        vmNicId=$(az vm nic list --resource-group $resourceGroup --vm-name $vmWeb$i --query [].id -o tsv)
        vmNicName=${vmNicId##*/}

        PRIVATE_IP=$(az vm list-ip-addresses --name $vmWeb$i --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
        PRIVATE_IPS=$PRIVATE_IPS$PRIVATE_IP"[7800]"
        CMD_TO_RUN=$CMD_TO_RUN"\n Command for $vmWeb$i \n scp infinispan.xml setup-vm.sh dguser@$PUBLIC_IP: \n ssh dguser@$PUBLIC_IP \n chmod +x setup-vm.sh \n ./setup-vm.sh \n ./infinispan/bin/server.sh -b 0.0.0.0 \n"
        if [ $i != $numVM ]; then
                PRIVATE_IPS=$PRIVATE_IPS","
        fi
done

echo "########################## Trying to update replicated host addresses ($PRIVATE_IPS) in infinispan.xml ##########################"
sed -e "s/--HOST_PRIVATE_IP/$PRIVATE_IPS/g" infinispan_sample.xml > infinispan.xml

echo "########################## Run the below commands for/on each VM to setup and run Infinispan Server. ##########################"
echo $CMD_TO_RUN
echo "###############################################################################################################################"
