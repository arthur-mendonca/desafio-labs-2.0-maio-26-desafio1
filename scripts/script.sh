# ==============================================================================
# Script de Automação - Formação AWS (Mentoria Desafio Labs 2.0)
# Objetivo: Criação de VPC Customizada, Sub-redes, IAM Role e Instância EC2 
# (bia-dev) posicionada especificamente na Zona de Disponibilidade B.
# ==============================================================================

# Definição de Variáveis
REGION="us-east-1"
AZ_A="${REGION}a"
AZ_B="${REGION}b"
VPC_CIDR="10.0.0.0/16"
SUBNET_A_CIDR="10.0.1.0/24"
SUBNET_B_CIDR="10.0.2.0/24"
AMI_OWNER="099720109477" # Canonical (Ubuntu)

echo "Iniciando a criação da infraestrutura na região $REGION..."

# 1. Criação da VPC Customizada
echo "Criando VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text --region $REGION)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=vpc-bia-desafio --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}' --region $REGION
echo "VPC criada com sucesso: $VPC_ID"

# 2. Criação do Gateway de Internet
echo "Criando Gateway de Internet..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $REGION)
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=igw-bia --region $REGION
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION
echo "Gateway de Internet anexado: $IGW_ID"

# 3. Criação das Sub-redes (Zonas A e B)
echo "Criando Sub-redes Públicas nas Zonas A e B..."
SUBNET_A_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_A_CIDR --availability-zone $AZ_A --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $SUBNET_A_ID --tags Key=Name,Value=bia-subnet-publica-a --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_A_ID --map-public-ip-on-launch --region $REGION

SUBNET_B_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_B_CIDR --availability-zone $AZ_B --query 'Subnet.SubnetId' --output text --region $REGION)
aws ec2 create-tags --resources $SUBNET_B_ID --tags Key=Name,Value=bia-subnet-publica-b --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_B_ID --map-public-ip-on-launch --region $REGION
echo "Sub-rede Zona A: $SUBNET_A_ID"
echo "Sub-rede Zona B: $SUBNET_B_ID"

# 4. Configuração da Tabela de Roteamento
echo "Configurando rotas públicas..."
RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value=rt-bia-publica --region $REGION
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION > /dev/null
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_A_ID --region $REGION > /dev/null
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_B_ID --region $REGION > /dev/null

# 5. Configuração de Segurança e IAM para o SSM
echo "Criando Função (Role) do IAM para o AWS Systems Manager (SSM)..."
TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam create-role --role-name Role-SSM-BiaDev --assume-role-policy-document "$TRUST_POLICY" > /dev/null 2>&1 || echo "Role já existe, ignorando criação."
aws iam attach-role-policy --role-name Role-SSM-BiaDev --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name Profile-SSM-BiaDev > /dev/null 2>&1 || echo "Instance profile já existe, ignorando criação."
aws iam add-role-to-instance-profile --instance-profile-name Profile-SSM-BiaDev --role-name Role-SSM-BiaDev > /dev/null 2>&1 || true

echo "Criando Grupo de Segurança (sem portas de entrada)..."
SG_ID=$(aws ec2 create-security-group --group-name sg-bia-dev --description "SG para acesso exclusivo via SSM" --vpc-id $VPC_ID --query 'GroupId' --output text --region $REGION)

# 6. Lançamento da Instância EC2
echo "Aguardando 10 segundos para a propagação das políticas do IAM..."
sleep 10

echo "Buscando a imagem (AMI) mais recente do Ubuntu 22.04 LTS..."
AMI_ID=$(aws ec2 describe-images --region $REGION --owners $AMI_OWNER --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)

echo "Lançando a máquina de trabalho (bia-dev) na Sub-rede B..."
INSTANCE_ID=$(aws ec2 run-instances \\
    --image-id $AMI_ID \\
    --count 1 \\
    --instance-type t2.micro \\
    --subnet-id $SUBNET_B_ID \\
    --security-group-ids $SG_ID \\
    --iam-instance-profile Name=Profile-SSM-BiaDev \\
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bia-dev}]' \\
    --query 'Instances[0].InstanceId' \\
    --output text \\
    --region $REGION)

echo "=============================================================================="
echo "Execução Concluída com Sucesso!"
echo "A instância $INSTANCE_ID está sendo inicializada na Zona B."
echo "Você poderá se conectar a ela via AWS Systems Manager (SSM) no console da AWS."
echo "=============================================================================="

